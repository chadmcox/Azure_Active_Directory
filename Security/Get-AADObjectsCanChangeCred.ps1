connect-mggraph
$Graph = Get-MgBetaServicePrincipal -filter "appId eq '00000003-0000-0000-c000-000000000000'"
#get the permission IDs
$app_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ("Application.ReadWrite.All")}


Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graph.id -All | `
    where {$_.AppRoleId -in ($app_permissions.id)} | select PrincipalDisplayName, PrincipalId -Unique | foreach{
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

$roles = '158c047a-c907-4556-b7ef-446551a6b5f7', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', 'd29b2b05-8046-44ba-8758-1e26182fcf32', `
    '4ba39ca4-527c-499a-b93d-d9b492c50246', '62e90394-69f5-4237-9190-012177145e10', 'c4e39bd9-1100-46d3-8c65-fb160da0071f', '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'

$results = Get-MgBetaDirectoryRole -all | where {$_.RoleTemplateId -in $roles} -pv role | foreach{
    Get-MgBetaDirectoryRoleMember -DirectoryRoleId $_.Id | foreach{$_ | select -expandproperty AdditionalProperties | `
        convertto-json| convertfrom-json}  | select displayName, "@odata.type",appid, @{N="via";Expression={"Role Member of $($role.displayname)"}}
  }

$results | select displayName, via -unique

$results | where {$_."@odata.type" -eq "#microsoft.graph.servicePrincipal"} | foreach{
    Get-MgBetaServicePrincipal -filter "appId eq '$($_.appid)'" -ExpandProperty owners | foreach{
        $app = $null;$app = $_
        ($app.owners).id | select @{N="appid";Expression={$app.appid}}, `
                @{N="displayname";Expression={(Get-MgBetaDirectoryObjectById -Ids $_ | select -ExpandProperty AdditionalProperties | convertto-json | convertfrom-json).displayname}}, `
                @{N="PublisherName";Expression={$app.PublisherName}},@{N="via";Expression={"Owner of $($app.displayname)"}}
    }
}  | select DisplayName,via -Unique
