param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

$appids = "00000002-0000-0000-c000-000000000000"
$graph = Get-MgBetaServicePrincipal -Filter "appId eq '$appids'"
$app_permissions = $Graph | select -ExpandProperty approles | select * -Unique | group id -AsHashTable -AsString

$directappassignment = ($Graph | foreach {Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $_.id -All |  where {$app_permissions.containskey($_.AppRoleId)} | `
    where {!($_.PrincipalDisplayName -like "*Microsoft Assessments*")} | `
    select PrincipalType, PrincipalId, PrincipalDisplayName,@{N="perm";Expression={$app_permissions[$_.AppRoleId].value}}}).PrincipalId

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

$sps = Get-MgBetaServicePrincipal -Filter "AccountEnabled eq true" -all -ExpandProperty owners | `
     select `
    id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname,AppRoleAssignmentRequired,SignInAudience,preferredSingleSignOnMode, `
    @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="OwnerId";E={($_.owners).id -join(";")}}

$permissions = ($Graph | select -ExpandProperty approles | select * -Unique).value

$directappassignment = $directappassignment + (Get-MgBetaDirectoryRecommendation -all | where {$_.status -eq "active" -and $_.displayname -in ("Migrate Service Principals from the retiring Azure AD Graph APIs to Microsoft Graph","Migrate Applications from the retiring Azure AD Graph APIs to Microsoft Graph")} | foreach{
    Get-MgBetaDirectoryRecommendationImpactedResource -RecommendationId $_.id -all | where {$_.status -eq "active"} | select Id, Displayname
}).id

$directappassignment = $directappassignment + (Get-MgBetaDirectoryRole | where {$_.RoleTemplateId -in ("88d8e3e3-8f55-4a1e-953a-9b9898b8876b","9360feb5-f418-4baa-8175-e2a00bac4301")} | foreach{
    Get-MgBetaDirectoryRoleMember -DirectoryRoleId $_.Id -all | where {($_.AdditionalProperties| convertto-json -Depth 99 | convertfrom-json)."@odata.type" -like "*servicePrincipal*"} } ).id 

$count = $sps.count; $i=0
$sps | where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a') -and $_.appDisplayname -ne "Microsoft Assessments"} | `
    where{$sp=$null; $sp=$_; $perms = $null; $perms = $null
   write-host "$($sp.displayname) remaining: $($count - $i) of $count"; $i++
   ($sp | where {$_.servicePrincipalType -eq 'Application'} | foreach{Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $_.id -PipelineVariable AADOPG | where {$_.resourceId -eq $Graph.id} | select * -first 1}) -or ($sp.id -in $directappassignment)
} | export-csv .\service_principals_with_azureadgraph_permission.csv -NoTypeInformation
