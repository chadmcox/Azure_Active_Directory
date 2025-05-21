#Requires -Modules AzureADPreview
<#
  this script will return signins from the aad sign in log for a single user for the last 24 hours
#>
Param($user=$(read-host "Enter Users email"), $querydate=$(get-date (get-date).AddDays(-1) -Format yyyy-MM-dd))

#check to see if already logged into AAD prompt if not
if(!((Get-AzureADTenantDetail).objectid)){connect-azuread}

Get-AzureADAuditSignInLogs -Filter "userPrincipalName eq '$user' and createdDateTime gt $querydate" -all $true | select `
  CreatedDateTime, UserDisplayName,IsInteractive, ClientAPPUsed, AppDisplayName, ipAddress, @{N="Displayname";E={$_.DeviceDetail.displayname}}, `
  conditionalaccessstatus, @{N="CAP";E={$_.AppliedConditionalAccessPolicies | select displayname, result | out-string}}
