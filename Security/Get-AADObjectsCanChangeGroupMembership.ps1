connect-mggraph

#get the graph id
$Graph = Get-MgBetaServicePrincipal -filter "appId eq '00000003-0000-0000-c000-000000000000'"
#get the permission IDs
$group_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ("GroupMember.ReadWrite.All","Group.ReadWrite.All")}


Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graph.id -All | `
    where {$_.AppRoleId -in ($group_permissions.id)} | select PrincipalDisplayName, PrincipalId -Unique | foreach{
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

$roles = '810a2642-a034-447f-a5e8-41beaa378541',',11451d60-acb2-45eb-a7d6-43d0f0125c13','45d8d3c5-c802-45c6-b32a-1d70b5e1e86e', `
  '744ec460-397e-42ad-a462-8b3f9747a02c', 'b5a8dcf3-09d5-43a9-a639-8e29ef291470', 'fdd7a751-b60b-444a-984c-02652fe8fa1c', `
  '69091246-20e8-4a56-aa4d-066075b2a7a8', 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c', '29232cdf-9323-42fd-ade2-1d097af3e4de', `
  '9360feb5-f418-4baa-8175-e2a00bac4301', 'fe930be7-5e62-47db-91af-98c3a49a38b1', '62e90394-69f5-4237-9190-012177145e10'

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
