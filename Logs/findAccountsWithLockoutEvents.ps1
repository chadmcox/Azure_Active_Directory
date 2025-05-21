Get-AzureADAuditSignInLogs -Filter "status/errorCode eq 50053" -All $true | select `
  CreatedDateTime, UserDisplayName,IsInteractive, ClientAPPUsed, AppDisplayName, ipAddress, @{N="Displayname";E={$_.DeviceDetail.displayname}}, `
  conditionalaccessstatus, @{N="Status";E={$_.Status.FailureReason}}
