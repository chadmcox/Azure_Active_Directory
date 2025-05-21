//Reference how to update the privuserlist
//https://github.com/chadmcox/Azure_AD_Conditional_Access_Policies/blob/main/anothertry.md#create-list-of-privileged-users-for-the-kql-designed-to-search-for-privileged-user-impact


let privusers = pack_array("**replace this with the results from the privuser.txt found from the powershell cmdlets**");
SigninLogs 
| where TimeGenerated > ago(14d) and UserId  in~ (privusers) and ResultType == 0 
| extend trustType = tostring(parse_json(DeviceDetail).trustType) 
| extend isCompliant = tostring(parse_json(DeviceDetail).isCompliant) 
| extend TrustedLocation = tostring(iff(NetworkLocationDetails contains 'trustedNamedLocation', 'trustedNamedLocation',''))
| extend os = tostring(parse_json(DeviceDetail).operatingSystem) 
| where isCompliant <> 'true' and trustType <> "Hybrid Azure AD joined"  
| distinct AppDisplayName,UserPrincipalName,ConditionalAccessStatus,AuthenticationRequirement, TrustedLocation, trustType,isCompliant,os, Category
