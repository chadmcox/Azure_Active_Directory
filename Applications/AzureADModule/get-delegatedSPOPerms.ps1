Connect-AzureAD

$permissions = "Sites.FullControl.All","Sites.Manage.All","Sites.Read.All","Sites.ReadWrite.All","Files.Read.All","Files.ReadWrite.All","File.Read.All"

$sps = Get-AzureADServicePrincipal -filter "servicePrincipalType eq 'Application'" -all $true | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerTenantId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')-and $_.appDisplayname -ne "Microsoft Assessments"}

$sps | where{$sp=$null; $sp=$_
   Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $sp.objectid -PipelineVariable AADOPG | foreach{
        $AADOPG.scope -split " " | where {$_ -in $permissions}
   }
} | select objectid, displayname, PublisherName, AccountEnabled | export-csv .\spo_delegated_permissions.csv -NoTypeInformation
