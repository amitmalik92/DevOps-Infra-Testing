terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# 2. Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-central-monitoring"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 3. Action Group for Alert Notifications
resource "azurerm_monitor_action_group" "ag" {
  name                = "ag-ops-team"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "OpsAlerts"

  email_receiver {
    name                    = "AdminEmail"
    email_address           = var.action_group_email
    use_common_alert_schema = true
  }
}

# 4. Alert Rule 1: High CPU Usage (> 85%)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "cpu_alert" {
  name                = "sqr-high-cpu-usage"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  scopes              = [azurerm_log_analytics_workspace.law.id]
  severity            = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
      Perf
      | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
      | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
    QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "AvgCPU"
    operator                = "GreaterThan"
    threshold               = 85

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
  }
}

# 5. Alert Rule 2: Low Free Disk Space (< 10%)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "disk_alert" {
  name                = "sqr-low-disk-space"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  scopes              = [azurerm_log_analytics_workspace.law.id]
  severity            = 1
  evaluation_frequency = "PT15M"
  window_duration      = "PT15M"

  criteria {
    query = <<-QUERY
      Perf
      | where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
      | summarize MinFreeSpace = min(CounterValue) by Computer, InstanceName, bin(TimeGenerated, 15m)
    QUERY

    time_aggregation_method = "Minimum"
    metric_measure_column   = "MinFreeSpace"
    operator                = "LessThan"
    threshold               = 10

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
  }
}

# 6. Alert Rule 3: VM Offline (Missing Heartbeat)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "heartbeat_alert" {
  name                = "sqr-vm-heartbeat-missing"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  scopes              = [azurerm_log_analytics_workspace.law.id]
  severity            = 0
  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"

  criteria {
    query = <<-QUERY
      Heartbeat
      | summarize LastHeartbeat = max(TimeGenerated) by Computer
      | extend MinutesSinceHeartbeat = datetime_diff('minute', now(), LastHeartbeat)
    QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "MinutesSinceHeartbeat"
    operator                = "GreaterThan"
    threshold               = 5

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
  }
}

# 7. Data Collection Rule (DCR) for Windows VMs
resource "azurerm_monitor_data_collection_rule" "dcr_windows" {
  name                = "dcr-windows-vm-monitoring"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                 = "central-law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = ["central-law-destination"]
  }

  data_sources {
    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes",
        "\\LogicalDisk(*)\\% Free Space"
      ]
      name                          = "perfCounterDataSource"
    }

    windows_event_log {
      streams        = ["Microsoft-Event"]
      x_path_queries = [
        "System![System[(Level=1 or Level=2 or Level=3)]]",
        "Application![System[(Level=1 or Level=2)]]"
      ]
      name           = "eventLogDataSource"
    }
  }
}