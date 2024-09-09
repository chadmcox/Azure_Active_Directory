param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All","DirectoryRecommendations.Read.All"
}
cd $defaultpath

Get-MgBetaDirectoryRecommendation -all | where {$_.status -eq "active" -and $_.displayname -eq "Remove unused applications"} | foreach{
    Get-MgBetaDirectoryRecommendationImpactedResource -RecommendationId $_.id -all | where {$_.status -eq "active"} | select Id, Displayname
} | export-csv .\recommendation_remove_unused_applications.csv -NoTypeInformation
