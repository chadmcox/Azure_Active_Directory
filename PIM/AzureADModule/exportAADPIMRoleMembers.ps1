#Requires -Modules AzureADPreview
<#
  This script will export all members out of every role in Azure PIM. Use this if you are using PIM if not use
  https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory_Scripts/master/Roles/ExportAADDirectoryRoleMembers.ps1
#>
Param($report="$env:userprofile\Documents\AADPIMRoleMembers.csv")

#check to see if already logged into AAD prompt if not
try{Get-AzureADTenantDetail}catch{connect-azuread}

#get all privilaged role membersrole members
Get-AzureADMSPrivilegedRoleDefinition -ProviderId "aadRoles" -ResourceId (Get-AzureADTenantDetail).objectid -pv role | foreach{
  write-host "Expanding $($role.displayname)"
    Get-AzureADMSPrivilegedRoleAssignment -ProviderId "aadRoles" -ResourceId (Get-AzureADTenantDetail).objectid `
        -filter "RoleDefinitionId eq '$($role.id)'" -pv mem | foreach{
            Get-AzureADObjectByObjectId -ObjectIds $mem.subjectid | select @{N="Role";E={$role.displayname}}, `
                @{N="Member";E={$_.displayname}}, userprincipalname, objecttype, @{N="AssignmentState";E={$mem.AssignmentState}}, `
                @{N="MemberType";E={$mem.MemberType}}, @{N="EndDateTime";E={$mem.EndDateTime}}
        }
} | export-csv $report -notypeinformation
