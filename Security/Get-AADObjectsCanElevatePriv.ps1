connect-mggraph
#get the graph id
$Graph = Get-MgBetaServicePrincipal -filter "appId eq '00000003-0000-0000-c000-000000000000'"
#get the permission IDs
$role_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ("AppRoleAssignment.ReadWrite.All","RoleManagement.ReadWrite.Directory")}


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
$roles = '62e90394-69f5-4237-9190-012177145e10','4ba39ca4-527c-499a-b93d-d9b492c50246','e00e864a-17c5-4a4b-9c06-f5b95a8d5bd8', `
  '9360feb5-f418-4baa-8175-e2a00bac4301', 'd29b2b05-8046-44ba-8758-1e26182fcf32', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', `
  'e8611ab8-c189-46e8-94e1-60213ab1f814', '158c047a-c907-4556-b7ef-446551a6b5f7', '8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2', `
  '45d8d3c5-c802-45c6-b32a-1d70b5e1e86e'

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
