$ResourceId = (Get-MgBetaServicePrincipal -filter "AppId eq '00000002-0000-0000-c000-000000000000'" | select `
    @{N="SPid";E={$_.id}},@{N="SP";E={$_.displayname}}).SPid

Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ResourceId | select `
    PrincipalDisplayName, PrincipalId, PrincipalType, ResourceDisplayName, ResourceId
