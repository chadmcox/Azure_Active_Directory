try{Get-AzureADCurrentSessionInfo}
catch{Connect-azuread | out-null}

Get-AzureADDirectoryRole -Filter "RoleTemplateId eq 'd29b2b05-8046-44ba-8758-1e26182fcf32'" | Get-AzureADDirectoryRoleMember -pv mem | foreach{
    write-host "Getting logs for $($mem.userprincipalname)"
    try{Get-AzureADAuditSignInLogs -Filter "userId eq '$($mem.objectid)'" -all $true | select UserPrincipalName, IpAddress}catch{}
    Start-Sleep -Seconds 3
} | select UserPrincipalName, IpAddress -unique
