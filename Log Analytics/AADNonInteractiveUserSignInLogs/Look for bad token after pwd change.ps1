AADNonInteractiveUserSignInLogs
| where ResultType <> 0
| where TimeGenerated > ago(14d)
| where AppDisplayName == 'Windows Sign In'
| extend DeviceName = tostring(parse_json(DeviceDetail).displayName) 
| summarize countoffailures = count() by UserPrincipalName,startofday(TimeGenerated), DeviceName
| where countoffailures > 50000
| order by TimeGenerated desc 
