connect-azuread
Get-AzureADUser -Filter "userType eq 'Guest'" -All $true -PipelineVariable user | foreach{
    Get-AzureADUserMembership -ObjectId $user.objectid -all $true | select `
        @{N="GuestDisplayname";E={$user.displayname}}, `
        @{N="GuestUserPrincipalName";E={$user.userprincipalname}}, `
        @{N="GuestCreationType";E={$user.CreationType}}, `
        @{N="GuestUserState";E={$user.UserState}}, `
        objecttype, displayname
    Get-AzureADUserAppRoleAssignment -ObjectId $user.objectid -all $true | select `
        @{N="GuestDisplayname";E={$user.displayname}}, `
        @{N="GuestUserPrincipalName";E={$user.userprincipalname}}, `
        @{N="GuestCreationType";E={$user.CreationType}}, `
        @{N="GuestUserState";E={$user.UserState}}, `
        objecttype, @{N="displayname";E={$_.ResourceDisplayName}}
} | export-csv .\guestaccess.csv -NoTypeInformation
