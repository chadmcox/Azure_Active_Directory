connect-azuread
$appids = "00000003-0000-0000-c000-000000000000","00000002-0000-0ff1-ce00-000000000000"
$Graph = $appids | foreach {Get-AzureADServicePrincipal -filter "appId eq '$($_)'"}
$permissions = "Mail.Read","Mail.Read.Shared","Mail.ReadBasic","Mail.ReadBasic.All","Mail.ReadWrite","Mail.ReadWrite.Shared","Mail.Send", `
    "Mail.Send.Shared","MailboxSettings.Read","MailboxSettings.ReadWrite","email","EWS.AccessAsUser.All","Exchange.Manage"
$app_permissions = $Graph | select -ExpandProperty approles | select * | where {$_.value -in ($permissions)}

$Graph | foreach {Get-AzureADServiceAppRoleAssignment -ObjectId $_.objectid -All $true |  where {$_.id -in $app_permissions.id} | `
    where {!($_.PrincipalDisplayName -like "*Microsoft Assessments*")} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName} | export-csv .\exo_assigned_permissions.csv -NoTypeInformation
