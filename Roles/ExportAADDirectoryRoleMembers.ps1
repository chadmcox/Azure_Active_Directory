#Requires -Modules AzureADPreview
<#
  This script will just export all members out of every role in Azure AD.
  if use pim consider using the PIM related script this will not show elgible
  assignments
#>

Param($report="$env:userprofile\Documents\AzureAD_Directory_Role_Members.csv")

#check to see if already logged into AAD prompt if not
if(!((Get-AzureADTenantDetail).objectid)){connect-azuread}


Get-AzureADDirectoryRole -pv dr | Get-AzureADDirectoryRoleMember | select `
  @{N="Role";E={if($dr.displayname -eq "Company Administrator"){"Global Administrator"}else{$dr.displayname}}}, `
    Displayname, Userprincipalname, objecttype | export-csv $report -notypeinformation
    
