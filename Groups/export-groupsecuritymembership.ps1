param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$start = get-date

write-host "Starting $(get-date)"

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
} | export-csv ".\group_membership_groups.csv" -NoTypeInformation

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
} | export-csv ".\group_membership_users.csv" -NoTypeInformation

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
} | export-csv ".\group_membership_guests.csv" -NoTypeInformation

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
} | export-csv ".\group_membership_devices.csv" -NoTypeInformation

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
} | export-csv ".\group_membership_serviceprincipals.csv" -NoTypeInformation

write-host "Finished $(get-date) results should be found in $defaultpath"
