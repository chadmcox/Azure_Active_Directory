connect-azuread
$appids = "00000003-0000-0000-c000-000000000000","00000003-0000-0ff1-ce00-000000000000"
$Graph = $appids | foreach {Get-AzureADServicePrincipal -filter "appId eq '$($_)'"}
$permissions = "Sites.FullControl.All","Sites.Manage.All","Sites.Read.All","Sites.ReadWrite.All","Files.Read.All","Files.ReadWrite.All","File.Read.All"
$app_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ($permissions)}

$Graph | foreach {Get-AzureADServiceAppRoleAssignment -ObjectId $_.objectid -All $true |  where {$_.id -in $app_permissions.id} | `
    where {!($_.PrincipalDisplayName -like "*Microsoft Assessments*")} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName} | export-csv .\spo_assigned_permissions.csv -NoTypeInformation
