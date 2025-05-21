Connect-AzureAD
$sps = Get-AzureADServicePrincipal -filter "servicePrincipalType eq 'Application'" -all $true | `
    where {$_.PublisherName -like "*Microsoft*" -or !($_.PublisherName -eq "Microsoft Accounts") -and $_.AppOwnerTenantId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'}

$sps | where {Get-AzureADServicePrincipalOwner -ObjectId $_.objectid} | select objectid, displayname, PublisherName, AccountEnabled | export-csv .\builtin_apps_have_owners.csv -NoTypeInformation

