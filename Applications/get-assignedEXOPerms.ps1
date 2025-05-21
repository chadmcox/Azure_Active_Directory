param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
$appids = "00000003-0000-0000-c000-000000000000","00000002-0000-0ff1-ce00-000000000000"
$Graph = $appids | foreach {Get-MGBetaServicePrincipal -filter "appId eq '$($_)'"}
$permissions = "Mail.Read","Mail.Read.Shared","Mail.ReadBasic","Mail.ReadBasic.All","Mail.ReadWrite","Mail.ReadWrite.Shared","Mail.Send", `
    "Mail.Send.Shared","MailboxSettings.Read","MailboxSettings.ReadWrite","email","EWS.AccessAsUser.All","Exchange.Manage","full_access_as_app"
$app_permissions = $Graph | select -ExpandProperty approles | select * -Unique | where {$_.value -in ($permissions)} | group id -AsHashTable -AsString

$Graph | foreach {Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $_.id -All |  where {$app_permissions.containskey($_.AppRoleId)} | `
    where {!($_.PrincipalDisplayName -like "*Microsoft Assessments*")} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName,@{N="perm";Expression={$app_permissions[$_.AppRoleId].value}}} | export-csv .\exo_assigned_permissions.csv -NoTypeInformation


