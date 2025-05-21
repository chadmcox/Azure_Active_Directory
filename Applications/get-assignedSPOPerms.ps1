param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
$appids = "00000003-0000-0000-c000-000000000000","00000003-0000-0ff1-ce00-000000000000"
$Graph = $appids | foreach {Get-MGBetaServicePrincipal -filter "appId eq '$($_)'"}
$permissions = "Sites.FullControl.All","Sites.Manage.All","Sites.Read.All","Sites.ReadWrite.All","Files.Read.All","Files.ReadWrite.All","File.Read.All"
$app_permissions = $Graph | select -ExpandProperty approles | select * -Unique | where {$_.value -in ($permissions)} | group id -AsHashTable -AsString

$Graph | foreach {Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $_.id -All |  where {$app_permissions.containskey($_.AppRoleId)} | `
    where {!($_.PrincipalDisplayName -like "*Microsoft Assessments*")} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName,@{N="perm";Expression={$app_permissions[$_.AppRoleId].value}}} | export-csv .\spo_assigned_permissions.csv -NoTypeInformation


