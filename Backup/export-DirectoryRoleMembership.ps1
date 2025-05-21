function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Policy.Read.All","User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All","Group.Read.All","Application.Read.All", "AuditLog.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All" -Environment $mg_env.name
}

#login
login-MSGraph

Get-MgBetaDirectoryRole -All | foreach{$role = $null;$role = $_
    Get-MgBetaDirectoryRoleMember -DirectoryRoleId $role.id -Property id,displayName,userPrincipalName | foreach{
        $rolemember = $null; $rolemember = $_
        $rolemember.AdditionalProperties | ConvertTo-Json | convertfrom-json | select `
        @{n='RoleId';e={$role.id}}, `
        @{n='RoleTemplateId';e={$role.RoleTemplateId}}, `
        @{n='RoleDisplayName';e={$role.DisplayName}}, `
        @{n='RoleMemberType';e={$_."@odata.type"}}, `
        @{n='RoleMemberId';e={$rolemember.Id}}, `
        @{n='RoleMemberDisplayName';e={$_.displayName}}, `
        @{n='RoleMemberUPN';e={$_.userPrincipalName}}
    }
} | export-csv .\directoryrolemembers.csv -notypeinformation
