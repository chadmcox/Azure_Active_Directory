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

write-host "Starting group lookup export $(get-date)"
Get-MgBetaGroup -filter "SecurityEnabled eq true" -all -Property id, displayName, securityEnabled,onPremisesSyncEnabled | select id, displayName, securityEnabled,onPremisesSyncEnabled | export-csv .\grp.tmp -NoTypeInformation

write-host "Starting group hash table $(get-date)"
$grp_hash = import-csv .\grp.tmp | group id -AsHashTable -AsString

write-host "Starting group transitiveMemberOf export $(get-date)"
Get-MgBetaGroup -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | where {$grp_hash.ContainsKey("$($_)")} | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"group"}}, `
        @{Name="GroupId";Expression={$_}}, `
        @{Name="groupName";Expression={$grp_hash[$_].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_].onPremisesSyncEnabled}}
} | export-csv ".\groupmembershipgroups.csv" -NoTypeInformation

write-host "Starting user transitiveMemberOf export $(get-date)"
Get-MgBetaUser -filter "userType eq 'Member' and AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | where {$grp_hash.ContainsKey("$($_)")} | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"user"}}, `
        @{Name="GroupId";Expression={$_}}, `
        @{Name="groupName";Expression={$grp_hash[$_].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_].onPremisesSyncEnabled}}
} | export-csv ".\groupmembershipusers.csv" -NoTypeInformation

write-host "Starting guest transitiveMemberOf export $(get-date)"
Get-MgBetaUser -filter "userType eq 'Guest' and AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | where {$grp_hash.ContainsKey("$($_)")} | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"guest"}}, `
        @{Name="GroupId";Expression={$_}}, `
        @{Name="groupName";Expression={$grp_hash[$_].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_].onPremisesSyncEnabled}}
} | export-csv ".\groupmembershipguests.csv" -NoTypeInformation

write-host "Starting device transitiveMemberOf export $(get-date)"
Get-MgBetaDevice -filter "AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | where {$grp_hash.ContainsKey("$($_)")} | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"device"}}, `
        @{Name="GroupId";Expression={$_}}, `
        @{Name="groupName";Expression={$grp_hash[$_].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_].onPremisesSyncEnabled}}
} | export-csv ".\groupmembershipdevices.csv" -NoTypeInformation

write-host "Starting sp transitiveMemberOf export $(get-date)"
Get-MgBetaServicePrincipal -filter "AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | where {$grp_hash.ContainsKey("$($_)")} | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"serviceprincipal"}}, `
        @{Name="GroupId";Expression={$_}}, `
        @{Name="groupName";Expression={$grp_hash[$_].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_].onPremisesSyncEnabled}}
} | export-csv ".\groupmembershipserviceprincipals.csv" -NoTypeInformation
