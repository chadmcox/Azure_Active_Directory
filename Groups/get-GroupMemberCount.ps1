param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\member_count_groups.csv"

$groups = Get-MgBetaGroup -All -Property Id,DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime, isAssignableToRole,onPremisesSecurityIdentifier | select  Id,DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier
$totalcount = $groups.count
$i = 0
 $groups | ForEach-Object {$count=0 ; $i++
    Write-host "Checking $($_.displayname) $i of $totalcount"
    $count = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups/$($_.Id)/members/`$count" -Headers @{ConsistencyLevel="eventual"})
    Write-host "Checking $($_.displayname) has $count members"
        $_ | Select-Object Id, DisplayName,onPremisesSyncEnabled,mailEnabled, SecurityEnabled, @{N="membercount";E={$count}}, onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier

} | export-csv $file1 -notypeinformation
