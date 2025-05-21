connect-azuread
$roles = '158c047a-c907-4556-b7ef-446551a6b5f7', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', 'd29b2b05-8046-44ba-8758-1e26182fcf32', `
    '4ba39ca4-527c-499a-b93d-d9b492c50246', '62e90394-69f5-4237-9190-012177145e10', 'c4e39bd9-1100-46d3-8c65-fb160da0071f', '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'

  Get-AzureADDirectoryRole | where {$_.RoleTemplateId -in $roles} -pv role | foreach{
    Get-AzureADDirectoryRoleMember -objectid $_.objectId | select objecttype, displayName, @{N="via";Expression={"Role Member of $($role.displayname)"}}
  } | select objecttype,DisplayName,via -Unique | export-csv .\role_members_can_change_creds.csv -NoTypeInformation



