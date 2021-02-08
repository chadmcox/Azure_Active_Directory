Get-AzureADAuditSignInLogs -Filter "ClientAppUsed eq 'Exchange ActiveSync' and appid eq '00000002-0000-0ff1-ce00-000000000000'" | `
    select UserPrincipalName,ClientAppUsed,AppDisplayName, @{N="Status";E={if($_.status.errorcode -eq 0){"Success"}else{"Error"}}}, `
    @{N="Device OS";E={$_.DeviceDetail.OperatingSystem}}, @{N="Device Browser";E={$_.DeviceDetail.Browser}}
    
Get-AzureADAuditSignInLogs -Filter "ClientAppUsed eq 'IMAP4' and appid eq '00000002-0000-0ff1-ce00-000000000000'" | `
    select UserPrincipalName,ClientAppUsed,AppDisplayName, @{N="Status";E={if($_.status.errorcode -eq 0){"Success"}else{"Error"}}}, `
    @{N="Device OS";E={$_.DeviceDetail.OperatingSystem}}, @{N="Device Browser";E={$_.DeviceDetail.Browser}}
    
Get-AzureADAuditSignInLogs -Filter "ClientAppUsed eq 'Other clients' and appid eq '00000002-0000-0ff1-ce00-000000000000'" | `
    select UserPrincipalName,ClientAppUsed,AppDisplayName, @{N="Status";E={if($_.status.errorcode -eq 0){"Success"}else{"Error"}}}, `
    @{N="Device OS";E={$_.DeviceDetail.OperatingSystem}}, @{N="Device Browser";E={$_.DeviceDetail.Browser}}
    
Get-AzureADAuditSignInLogs -Filter "ClientAppUsed eq 'Exchange Web Services' and appid eq '00000002-0000-0ff1-ce00-000000000000'" | `
    select UserPrincipalName,ClientAppUsed,AppDisplayName, @{N="Status";E={if($_.status.errorcode -eq 0){"Success"}else{"Error"}}}, `
    @{N="Device OS";E={$_.DeviceDetail.OperatingSystem}}, @{N="Device Browser";E={$_.DeviceDetail.Browser}}
