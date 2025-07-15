<#

this takes the file populated out of one environment from this script

https://github.com/chadmcox/Azure_Active_Directory/blob/master/PIM/exportAADPIMSettings.ps1

and can be used to duplicate the role to group mapping in another tenant.

#>

param($file=".\\PIM_Roles_to_PIM_Group_Mapping\pimrolegroupmapping.csv")
cd $path
$starttime = Get-Date


function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All","Group.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All","User.Read.All", `
        "UserAuthenticationMethod.Read.All" -Environment $mg_env.name
}


login-MSGraph
$context = get-mgcontext
#first create the groups and add to pim


import-csv $file | select groupName -unique | foreach{
    $gname = "$((($_.groupName).replace(' ','')))"
    $gname
    $group=$null;$group = get-mggroup -filter "DisplayName eq '$gname'"
    if(!($group){
    $group = New-MgGroup -DisplayName $gname -MailEnabled:$false -MailNickname  $gname  -SecurityEnabled -IsAssignableToRole
    }
    Register-MgPrivilegedAccessResource -PrivilegedAccessId AADGroups -ExternalId $group.Id
}

#create a role hash
$hash_roles = Get-MgPrivilegedAccessRoleDefinition -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | select DisplayName, Id | group DisplayName -AsHashTable -AsString
#grate a pag hash
$hash_pag = Get-MgPrivilegedAccessResource -PrivilegedAccessId AADGroups | select DisplayName, Id | group DisplayName -AsHashTable -AsString

#add the group to a role
import-csv $file -pv mapping | foreach{
    New-MgPrivilegedAccessRoleAssignmentRequest -PrivilegedAccessId AADRoles `
        -RoleDefinitionId $hash_roles[$mapping.roleName].id -subjectid $hash_pag[$mapping.groupName].id `
        -ResourceId $($context.TenantId) `
        -Type "AdminAdd" -AssignmentState "Active" `
        -Reason "Assign an Active role"
}
