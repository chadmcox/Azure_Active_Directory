#Requires -Modules AzureADPreview
<#
  this script will return signins from the aad sign in log for a single user for the last 24 hours
#>
Param($days=30)

#check to see if already logged into AAD prompt if not
if(!((Get-AzureADTenantDetail).objectid)){connect-azuread}

Get-AzureADApplicationSignInSummary -Days $days | sort SuccessfulSignInCount -Descending | out-gridview
