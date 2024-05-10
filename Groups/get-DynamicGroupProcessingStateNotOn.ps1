param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

Get-MgBetaGroup -filter "groupTypes/any(c:c eq 'DynamicMembership')" -all `
    -property Id, Displayname, OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId `
    -ExpandProperty owners | where {!($_.onPremisesSyncEnabled -eq $true) -and ($_.GroupTypes -contains "DynamicMembership") -and !($_.MembershipRuleProcessingState -eq 'On')} | select `
        Id, Displayname, OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole,MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId
