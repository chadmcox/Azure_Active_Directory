$aadgraph = Get-AzureADServicePrincipal -Filter "appId eq '00000002-0000-0000-c000-000000000000'"
Get-AzureADServicePrincipal -filter "servicePrincipalType eq 'Application'" -all $true | where {
    Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $_.objectid -All $true  | where {$_.resourceId -eq $aadgraph.objectid} | select * -First 1
} | select objectid, displayname, PublisherName | export-csv .\delegatedaadperms.csv -NoTypeInformation
