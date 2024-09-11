param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

#modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.Reports,Microsoft.Graph.Beta.Users,Microsoft.Graph.Beta.Applications
Write-host "Get all the service principals that have datetime populated"
$sps_lastsignin = Get-MgBetaReportServicePrincipalSignInActivity -all | where {$_.LastSignInActivity.LastSignInDateTime} | select appid, LastSignInActivity, `
        @{N="SignInActivityType";E={if($_.delegatedClientSignInActivity.lastSignInDateTime){"delegatedClient"
        }elseif($_.delegatedResourceSignInActivity.lastSignInDateTime){"delegatedResource"
        }elseif($_.applicationAuthenticationClientSignInActivity.lastSignInDateTime){"applicationAuthenticationClient"
        }elseif($_.applicationAuthenticationResourceSignInActivity.lastSignInDateTime){"applicationAuthenticationResource"
        }else{"unknown"}}}
write-host "Found SignInActivity for $($sps_lastsignin.count) service principals"
write-host "Build a hash table for quick lookup"
$sps_lastsignin_hash = $sps_lastsignin | select appid,signInActivityType -ExpandProperty LastSignInActivity | `
    select appid, @{N="LastSignInDateTime";E={$_.LastSignInDateTime}},signInActivityType | `
    group appid -AsHashTable -AsString

$app_recom_report = ".\entra_recommendation_remove_unused_applications.csv"
write-host "Exporting the stale apps from Entra Recommendations: $app_recom_report"
Get-MgBetaDirectoryRecommendation -all | where {$_.status -eq "active" -and $_.displayname -eq "Remove unused applications"} | foreach{
    Get-MgBetaDirectoryRecommendationImpactedResource -RecommendationId $_.id -all | where {$_.status -eq "active"} | select id, displayname, owner
} | export-csv $app_recom_report -NoTypeInformation

$recommendedsps_stale = (import-csv $app_recom_report).Id

$sp_report = ".\entra_app_activity_from_summary.csv"
write-host "Getting all applications/service principals and creating the report: $sp_report"
Get-MgBetaServicePrincipal -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')} | select `
    id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname,AppRoleAssignmentRequired,SignInAudience,preferredSingleSignOnMode, `
    @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    #@{N="OwnerId";E={($_.owners).id -join(";")}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | export-csv $sp_report -notypeinformation

$updated_recommendations_report = ".\entra_updated_recommendation_remove_unused_applications.csv"
write-host "creating a updated stale application recommendations report: $updated_recommendations_report"
import-csv $sp_report | where {$_.appid -in $recommendedsps_stale} | export-csv $updated_recommendations_report -NoTypeInformation

write-host "finished, results can be found here $($defaultdirectory)"
