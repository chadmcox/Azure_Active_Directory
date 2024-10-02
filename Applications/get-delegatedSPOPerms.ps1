param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
$permissions = "Sites.FullControl.All","Sites.Manage.All","Sites.Read.All","Sites.ReadWrite.All","Files.Read.All","Files.ReadWrite.All","File.Read.All", "Files.readwrite"

$sps = Get-MGBetaServicePrincipal -filter "servicePrincipalType eq 'Application'" -all | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')-and $_.appDisplayname -ne "Microsoft Assessments"}

$sps | where{$sp=$null; $sp=$_
   Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $sp.id -PipelineVariable AADOPG | foreach{
        $_.scope -split " " | where {$_ -in $permissions}
   }
} | select appid,id, displayname, PublisherName, AccountEnabled | export-csv .\spo_delegated_permissions.csv -NoTypeInformation
