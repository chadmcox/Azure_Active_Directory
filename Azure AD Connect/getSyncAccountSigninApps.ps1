try{Get-AzureADCurrentSessionInfo}
catch{Connect-azuread | out-null}

#this shows apps this account should not be logging into
Get-AzureADDirectoryRole -Filter "RoleTemplateId eq 'd29b2b05-8046-44ba-8758-1e26182fcf32'" | Get-AzureADDirectoryRoleMember -pv mem | foreach{
    write-host "Getting logs for $($mem.userprincipalname)"
    Get-AzureADAuditSignInLogs -Filter "userId eq '$($mem.objectid)' and appId ne 'cb1056e2-e479-49de-ae31-7812af012ed8'" -all $true -pv ssl
    Start-Sleep -Seconds 3
} | select UserPrincipalName, AppDisplayName -unique
