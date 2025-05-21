param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

Get-MgBetaGroup -filter "SecurityEnabled eq true" -all `
    -property Id, Displayname, onPremisesSyncEnabled, mailNickname, mailEnabled, SecurityEnabled, GroupTypes, IsAssignableToRole, membershipRule, owners `
    -ExpandProperty owners | where {!($_.onPremisesSyncEnabled -eq $true) -and ($_.GroupTypes -contains "DynamicMembership") -and !($_.GroupTypes -contains "Unified")} | select `
        Id, Displayname, mailNickname, mailEnabled, SecurityEnabled, GroupTypes, IsAssignableToRole, membershipRule, owners | convertto-json | Out-File .\backup_dynamic_groups_rules.json
