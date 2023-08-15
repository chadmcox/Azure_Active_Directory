Get-MgBetaGroup -filter "SecurityEnabled eq true" -all `
    -property Id, Displayname, onPremisesSyncEnabled, mailNickname, mailEnabled, SecurityEnabled, GroupTypes, IsAssignableToRole `
    -ExpandProperty appRoleAssignments | where {!($_.onPremisesSyncEnabled -eq $true) -and ($_.appRoleAssignments -like "*")} | select `
        Id, Displayname, mailNickname, mailEnabled, SecurityEnabled, GroupTypes, IsAssignableToRole, appRoleAssignments | convertto-json | Out-File .\backup_group_appRoleAssignments.json
