connect-azuread
Get-AzureADServicePrincipal -Filter "appId eq '00000002-0000-0000-c000-000000000000'" | foreach{
    Get-AzureADServiceAppRoleAssignment -ObjectId $_.ObjectId

} | select ResourceDisplayName, PrincipalDisplayName -Unique
