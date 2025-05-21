connect-azuread
$roles = '810a2642-a034-447f-a5e8-41beaa378541',',11451d60-acb2-45eb-a7d6-43d0f0125c13','45d8d3c5-c802-45c6-b32a-1d70b5e1e86e', `
  '744ec460-397e-42ad-a462-8b3f9747a02c', 'b5a8dcf3-09d5-43a9-a639-8e29ef291470', 'fdd7a751-b60b-444a-984c-02652fe8fa1c', `
  '69091246-20e8-4a56-aa4d-066075b2a7a8', 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c', '29232cdf-9323-42fd-ade2-1d097af3e4de', `
  '9360feb5-f418-4baa-8175-e2a00bac4301', 'fe930be7-5e62-47db-91af-98c3a49a38b1', '62e90394-69f5-4237-9190-012177145e10'

  Get-AzureADDirectoryRole | where {$_.RoleTemplateId -in $roles} -pv role | foreach{
    Get-AzureADDirectoryRoleMember -objectid $_.objectId | select objecttype, displayName, @{N="via";Expression={"Role Member of $($role.displayname)"}}
  } | select objecttype,DisplayName,via -Unique | export-csv .\role_members_can_change_group_membership.csv -NoTypeInformation



