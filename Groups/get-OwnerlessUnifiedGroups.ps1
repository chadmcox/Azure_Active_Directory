Get-MgBetaGroup -all `
    -property Id, Displayname, OnPremisesSyncEnabled, SecurityEnabled,GroupTypes,mailEnabled, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId `
    -ExpandProperty owners | where {!($_.owners -like "*") -and !($_.onPremisesSyncEnabled -eq $true) -and ($_.GroupTypes -contains "Unified")} | select `
        Id, Displayname, OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId, owners
