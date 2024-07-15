$start = get-date

write-host "Starting $(get-date)"

write-host "Starting group lookup export $(get-date)"
Get-MgBetaGroup -all -Property id, displayName, securityEnabled,onPremisesSyncEnabled | select id, displayName, securityEnabled,onPremisesSyncEnabled | export-csv .\grp.tmp -NoTypeInformation

write-host "Starting group transitiveMemberOf export $(get-date)"
Get-MgBetaGroup -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"group"}}, `
        @{Name="GroupId";Expression={$_}}
} | export-csv ".\tmp.tmp" -NoTypeInformation

write-host "Starting user transitiveMemberOf export $(get-date)"
Get-MgBetaUser -filter "userType eq 'Member' and AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"user"}}, `
        @{Name="GroupId";Expression={$_}}
} | export-csv ".\tmp.tmp" -NoTypeInformation -Append

write-host "Starting guest transitiveMemberOf export $(get-date)"
Get-MgBetaUser -filter "userType eq 'Guest' and AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"guest"}}, `
        @{Name="GroupId";Expression={$_}}
} | export-csv ".\tmp.tmp" -NoTypeInformation -Append

write-host "Starting device transitiveMemberOf export $(get-date)"
Get-MgBetaDevice -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"device"}}, `
        @{Name="GroupId";Expression={$_}}
} | export-csv ".\tmp.tmp" -NoTypeInformation -Append

write-host "Starting sp transitiveMemberOf export $(get-date)"
Get-MgBetaServicePrincipal -filter "AccountEnabled eq true" -ExpandProperty transitiveMemberOf -all | foreach{$o=$null;$o=$_
    $o.transitiveMemberOf.id | select `
        @{Name="ObjectId";Expression={$o.id}}, `
        @{Name="ObjectName";Expression={$o.displayname}}, `
        @{Name="ObjectType";Expression={"serviceprincipal"}}, `
        @{Name="GroupId";Expression={$_}}
} | export-csv ".\tmp.tmp" -NoTypeInformation -Append

write-host "Starting group hash table $(get-date)"
$grp_hash = import-csv .\grp.tmp | group id -AsHashTable -AsString
import-csv .\tmp.tmp | select `
    objectId, objectName, objectType, groupId, `
        @{Name="groupName";Expression={$grp_hash[$_.GroupId].displayName}}, `
        @{Name="groupSecurityEnabled";Expression={$grp_hash[$_.GroupId].securityEnabled}}, `
        @{Name="onPremisesGroup";Expression={$grp_hash[$_.GroupId].onPremisesSyncEnabled}} | export-csv '.\group_membership_report.csv' -NoTypeInformation

write-host "Finished $(get-date)"
