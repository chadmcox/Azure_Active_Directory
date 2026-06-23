param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\member_count_groups.csv"

$groups = Get-MgBetaGroup -All -Property Id,DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime, isAssignableToRole,onPremisesSecurityIdentifier | select  Id,DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier

 $groups | ForEach-Object {$count=0
    $count = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups/$($_.Id)/members/`$count" -Headers @{ConsistencyLevel="eventual"})

        $_ | Select-Object Id, DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled, @{N="membercount";E={$count}}, onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier

} | export-csv $file1 -notypeinformation
