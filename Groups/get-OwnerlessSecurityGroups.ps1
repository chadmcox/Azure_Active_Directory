param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

Get-MgBetaGroup -filter "SecurityEnabled eq true" -all `
    -property Id, Displayname, OnPremisesSyncEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId `
    -ExpandProperty owners | where {!($_.owners -like "*") -and !($_.onPremisesSyncEnabled -eq $true) -and !($_.GroupTypes -contains "Unified")} | select `
        Id, Displayname, OnPremisesSyncEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId, owners
