let timerange=14d;
SigninLogs
| where TimeGenerated > ago (timerange)
| where ResultType == 0
| where AppDisplayName <> "Windows Sign In"
| where AADTenantId == ResourceTenantId
| extend AuthMethod = tostring(parse_json(AuthenticationDetails)[0].authenticationMethod)
| where AuthMethod != "Previously satisfied"
| extend os = tostring(parse_json(DeviceDetail).operatingSystem) 
| extend trustType = tostring(parse_json(DeviceDetail).trustType) 
| extend isCompliant = tostring(parse_json(DeviceDetail).isCompliant) 
| summarize AuthenticationCount = count() by UserPrincipalName,UserDisplayName, startofday(TimeGenerated), os, trustType, isCompliant

