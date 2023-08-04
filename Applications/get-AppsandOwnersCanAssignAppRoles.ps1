connect-mggraph
#get the graph id
$Graph = Get-MgBetaServicePrincipal -filter "appId eq '00000003-0000-0000-c000-000000000000'"
#get the permission IDs
$role_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ("AppRoleAssignment.ReadWrite.All")}


Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graph.id -All | `
    where {$_.AppRoleId -in ($role_permissions.id)} | select PrincipalDisplayName, PrincipalId -Unique | foreach{
        Get-MgBetaServicePrincipal -serviceprincipalid $_.PrincipalId -ExpandProperty owners | foreach{
            $app = $null;$app = $_
            $app | select appid, displayname,PublisherName,@{N="via";Expression={"AppRoleAssignment"}}
            ($app.owners).id | select @{N="appid";Expression={$app.appid}}, `
                @{N="displayname";Expression={(Get-MgBetaDirectoryObjectById -Ids $_ | select -ExpandProperty AdditionalProperties | convertto-json | convertfrom-json).displayname}}, `
                @{N="PublisherName";Expression={$app.PublisherName}},@{N="via";Expression={"Owner of $($app.displayname)"}}
            (Get-MgBetaApplication -filter "appId eq '$($_.appid)'" -ExpandProperty owners | `
                select -expandproperty owners).id | select @{N="appid";Expression={$app.appid}}, `
                @{N="displayname";Expression={(Get-MgBetaDirectoryObjectById -Ids $_ | select -ExpandProperty AdditionalProperties | convertto-json | convertfrom-json).displayname}}, `
                @{N="PublisherName";Expression={$app.PublisherName}},@{N="via";Expression={"Owner of $($app.displayname)"}}
        }
    } | select DisplayName,via -Unique
