#Requires -Modules AzureADPreview
<#
  
#>
Param($report="$env:userprofile\Documents\AzureAD_Role_Membership_Changes.csv")

#check to see if already logged into AAD prompt if not
if(!((Get-AzureADTenantDetail).objectid)){connect-azuread}

Get-AzureADAuditDirectoryLogs -Filter "Category eq 'RoleManagement'" -All $true | select `
    ActivityDateTime, Category, ActivityDisplayName, Result, `
    @{N="InitiatedBy";E={if($_.InitiatedBy.user.DisplayName){$_.InitiatedBy.user.DisplayName}elseif($_.InitiatedBy.app.DisplayName){$_.InitiatedBy.app.DisplayName}else{$_.InitiatedBy.user.UserPrincipalName}}}, `
    @{N="UserPrincipalName";E={[string]($_).TargetResources.UserPrincipalname}}, `
    @{N="RoleName";E={(($_.targetresources.ModifiedProperties | where {$_.DisplayName -eq "Role.DisplayName"}).newvalue).replace('"','')}} | export-csv $report -NoTypeInformation

