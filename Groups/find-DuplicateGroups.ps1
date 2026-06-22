param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
   connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\original_groups.csv"
$file2 = ".\duplicate_groups.csv"
$file3 = ".\final_duplicate_groups.csv"

Get-MgBetaGroup -All -Filter "onPremisesSyncEnabled eq true" | select createdDateTime, displayName, expirationDateTime,onPremisesDomainName, onPremisesLastSyncDateTime, onPremisesNetBiosName, onPremisesSecurityIdentifier,onPremisesSyncEnabled, securityEnabled | export-csv $file1 -NoTypeInformation
import-csv $file1 | group displayname | select name, count | sort count -Descending | where count -gt 1 | export-csv $file2 -NoTypeInformation
$duplicate = import-csv $file2 | group name -AsHashTable -AsString

write-host "total duplicates $($duplicate.count)"
import-csv $file1 | where {$duplicate.Contains($_.displayname)} | export-csv $file3 -NoTypeInformation
