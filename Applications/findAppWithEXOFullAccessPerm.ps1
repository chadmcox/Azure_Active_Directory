connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All'

$ResourceId = (Get-MgServicePrincipal -filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'" | select `
    @{N="SPid";E={$_.id}},@{N="SP";E={$_.displayname}} -ExpandProperty approles | where value -eq 'full_access_as_app' | select *).SPid
$RoleID = (Get-MgServicePrincipal -filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'" | select `
    @{N="SPid";E={$_.id}},@{N="SP";E={$_.displayname}} -ExpandProperty approles | where value -eq 'full_access_as_app' | select *).id

Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ResourceId | where approleid -eq $RoleID | select `
    PrincipalDisplayName, PrincipalId, PrincipalType, ResourceDisplayName, ResourceId
