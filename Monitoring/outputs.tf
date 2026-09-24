output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "data_collection_rule_id" {
  value = azurerm_monitor_data_collection_rule.dcr_windows.id
}