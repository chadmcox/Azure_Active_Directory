$group_displayname = "changeme"
Get-AzureADAuditDirectoryLogs -filter "initiatedBy/user/displayName eq '$group_displayname'" | select ActivityDateTime, `
  @{N="User";E={($_.TargetResources.UserPrincipalName)[0]}},@{N="AddedtoGroup";E={$_.Result}} | `
    where {start-sleep -seconds 3;(!(Get-AzureADAuditDirectoryLogs -Filter "targetResources/any(tr:tr/UserPrincipalName eq '$($_.User)') and ActivityDisplayName eq 'Add user to feature rollout'"))}
