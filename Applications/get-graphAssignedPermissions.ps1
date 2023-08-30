connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
$appid = "00000003-0000-0000-c000-000000000000"
$spid = Get-MGServicePrincipal -filter "appId eq '$appid'"
$app_permissions = $spid | select -ExpandProperty approles | select * -Unique | group id -AsHashTable -AsString
Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $spid.id -All | where {$app_permissions.containskey($_.AppRoleId)} | `
  select PrincipalType, PrincipalId, PrincipalDisplayName,@{N="perm";Expression={$app_permissions[$_.AppRoleId].value}} | `
    export-csv .\graph_assigned_permissions.csv -NoTypeInformation
