connect-azuread
$appids = "00000003-0000-0000-c000-000000000000"
$Graph = $appids | foreach {Get-AzureADServicePrincipal -filter "appId eq '$($_)'"}

$app_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -like "*readwrite*"}

$Graph | foreach {Get-AzureADServiceAppRoleAssignment -ObjectId $_.objectid -All $true |  where {$_.id -in $app_permissions.id} | `
    where {Get-AzureADServicePrincipalOwner -ObjectId $_.PrincipalId} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName} | export-csv .\readwrite_assigned_permissions_has_owner.csv -NoTypeInformation
