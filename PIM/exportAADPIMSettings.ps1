param($path="$env:USERPROFILE\downloads")
cd $path
$starttime = Get-Date

Import-Module Microsoft.Graph.Identity.Governance

function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All","Group.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All","User.Read.All", `
        "UserAuthenticationMethod.Read.All" -Environment $mg_env.name
    Select-MgProfile -Name "beta"
}



login-MSGraph
$context = get-mgcontext


$pimroles = Get-MgPrivilegedAccessRoleDefinition -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | group id -AsHashTable -AsString
$pimgroups = Get-MgPrivilegedAccessResource -PrivilegedAccessId AADGroups | group id -AsHashTable -AsString
New-Item -ItemType directory -Name ".\PIM_Group"
#export group settings
foreach($pg in $pimgroups.keys){
    $pg
    $dir=$null; $dir = ".\PIM_Group\$($pimgroups[$pg].DisplayName)"
    try{New-Item -ItemType directory -Name "$dir"}catch{}
    Get-MgPrivilegedAccessRoleSetting -PrivilegedAccessId AADGroups -Filter "resourceId eq '$pg'" | select -last 1 | foreach{
        $_.AdminEligibleSettings | convertto-json -depth 99 | out-file "$dir\$($_.Id)_AdminEligibleSettings.json"
        $_.AdminMemberSettings | convertto-json -depth 99 | out-file "$dir\$($_.Id)_AdminMemberSettings.json"
        $_.UserMemberSettings | convertto-json -depth 99 | out-file "$dir\$($_.Id)_UserMemberSettings.json"
        $_.UserEligibleSettings | convertto-json -depth 99 | out-file "$dir\$($_.Id)_UserEligibleSettings.json"
    }
}

New-Item -ItemType directory -Name ".\PIM_Roles"
Get-MgPrivilegedAccessRoleSetting -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | foreach{
    $padid = $_.id
    $dir=$null; $dir = ".\PIM_Roles\$($pimroles[$_.RoleDefinitionId].DisplayName)"
    try{New-Item -ItemType directory -Name "$dir"}catch{}
    $_.AdminEligibleSettings | convertto-json -depth 99 | out-file "$dir\$($padid)_AdminEligibleSettings.json"
    $_.AdminMemberSettings | convertto-json -depth 99 | out-file "$dir\$($padid)_AdminMemberSettings.json"
    $_.UserMemberSettings | convertto-json -depth 99 | out-file "$dir\$($padid)_UserMemberSettings.json"
    $_.UserEligibleSettings | convertto-json -depth 99 | out-file "$dir\$($padid)_UserEligibleSettings.json"
}
