param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
$permissions = "Mail.Read","Mail.Read.Shared","Mail.ReadBasic","Mail.ReadBasic.All","Mail.ReadWrite","Mail.ReadWrite.Shared","Mail.Send", `
    "Mail.Send.Shared","MailboxSettings.Read","MailboxSettings.ReadWrite","EWS.AccessAsUser.All","Exchange.Manage"
$appids = "00000003-0000-0000-c000-000000000000","00000002-0000-0ff1-ce00-000000000000"

$sps = Get-MGBetaServicePrincipal -filter "servicePrincipalType eq 'Application'" -all | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')-and $_.appDisplayname -ne "Microsoft Assessments"}

$sps | where{$sp=$null; $sp=$_
   Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $sp.id -PipelineVariable AADOPG | foreach{
        $_.scope -split " " | where {$_ -in $permissions}
   }
} | select appid,id, displayname, PublisherName, AccountEnabled | export-csv .\exo_delegated_permissions.csv -NoTypeInformation
