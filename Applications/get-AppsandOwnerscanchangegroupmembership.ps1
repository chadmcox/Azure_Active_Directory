connect-mggraph

#get the graph id
$Graph = Get-MgBetaServicePrincipal -filter "appId eq '00000003-0000-0000-c000-000000000000'"
#get the permission IDs
$group_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ("GroupMember.ReadWrite.All","Group.ReadWrite.All")}


Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graph.id -All | `
    where {$_.AppRoleId -in ($group_permissions.id)} | select PrincipalDisplayName, PrincipalId -Unique | foreach{
        Get-MgBetaServicePrincipal -serviceprincipalid $_.PrincipalId -ExpandProperty owners | foreach{
            $_ | select appid, displayname,PublisherName, owners
            Get-MgBetaApplication -filter "appId eq '$($_.appid)'" -ExpandProperty owners | `
                select appid, displayname,PublisherName, owners | where {$_.owners -like "*"}
        }
    }
