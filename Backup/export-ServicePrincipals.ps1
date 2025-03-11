function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Policy.Read.All","User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All","Group.Read.All","Application.Read.All", "AuditLog.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All" -Environment $mg_env.name
}

#login
login-MSGraph

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
write-host "Build a hash table for entra recommended stale apps"
$sps_recommemded_stale_hash = Get-MgBetaDirectoryRecommendation -all | where {$_.status -eq "active" -and $_.displayname -eq "Remove unused applications"} | foreach{
    Get-MgBetaDirectoryRecommendationImpactedResource -RecommendationId $_.id -all | where {$_.status -eq "active"} | select id, displayname, owner, AddedDateTime
} | group id -AsHashTable -AsString
write-host "Build a hash table for to determin if app is oauth2"
$apps_flow_hash = Get-MgBetaApplication -all | Select-Object DisplayName, AppId, `
        @{Name="ImplicitGrant";Expression={($_.Web.ImplicitGrantSettings.EnableIdTokenIssuance -eq $true -or $_.Web.ImplicitGrantSettings.EnableAccessTokenIssuance -eq $true)}}, `
        @{Name="RedirectUris";Expression={$_.Web.RedirectUris}} | group AppId -ashashtable -asstring

write-host "Build a hash table to get the number of successful sign-ins to app for last 30 days"
$30daySignInCount = Get-MgBetaReportAzureAdApplicationSignInSummary -Period D30 | select id, SuccessfulSignInCount | where {$_.SuccessfulSignInCount -gt 0} | group id -AsHashTable -AsString
write-host "getting all enabled applications"
$servicePricipals = Get-MgBetaServicePrincipal  -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners
write-host "finding all apps that have preferred sign-in defined"
$servicePricipals | where {$_.preferredSingleSignOnMode -in ('saml','oidc','password')} | select @{N="Type";E={$_.preferredSingleSignOnMode}}, `
    Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="AzureAppService";E={$_.tags -contains "AppServiceIntegratedApp"}}, `
    @{N="EntraRecommendedStale";E={$sps_recommemded_stale_hash[$_.appid].AddedDateTime}}, `
    @{N="30DSuccessfulSignInCount";E={$30daySignInCount[$_.appid].SuccessfulSignInCount}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\applications.csv -NoTypeInformation
write-host "finding all the desktop apps"
# desktop apps
$servicePricipals | where {$_.ReplyUrls -like "*urn:ietf:wg:oauth:2.0:oob*"} | `
 where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a') -and $_.appDisplayname -ne "Microsoft Assessments"} | select `
    @{N="Type";E={"desktop"}}, `Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="AzureAppService";E={$_.tags -contains "AppServiceIntegratedApp"}}, `
    @{N="EntraRecommendedStale";E={$sps_recommemded_stale_hash[$_.appid].AddedDateTime}}, `
    @{N="30DSuccessfulSignInCount";E={$30daySignInCount[$_.appid].SuccessfulSignInCount}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\applications.csv -NoTypeInformation -Append

# openid apps
write-host "finding all the oidc apps"
$servicePricipals | where {!($_.ReplyUrls -like "*urn:ietf:wg:oauth:2.0:oob*")} | `
    where {!($_.preferredSingleSignOnMode -in ('saml','oidc','password'))} | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a') -and $_.appDisplayname -ne "Microsoft Assessments"} | 
    where {Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $_.id | where {$_.scope -like "*openid*"} | select -First 2} | select `
    @{N="Type";E={"oidc"}}, Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="AzureAppService";E={$_.tags -contains "AppServiceIntegratedApp"}}, `
    @{N="EntraRecommendedStale";E={$sps_recommemded_stale_hash[$_.appid].AddedDateTime}}, `
    @{N="30DSuccessfulSignInCount";E={$30daySignInCount[$_.appid].SuccessfulSignInCount}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\applications.csv -NoTypeInformation -Append
write-host "finding all the app proxies"
# app proxy
$servicePricipals | where {$_.Tags -Contains "WindowsAzureActiveDirectoryOnPremApp"} | `
    where {!($_.preferredSingleSignOnMode -in ('saml','oidc','password'))} | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a') -and $_.appDisplayname -ne "Microsoft Assessments"} | 
    where {Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $_.id | where {$_.scope -like "*openid*"} | select -First 2} | select `
    @{N="Type";E={"app-proxy"}}, Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="AzureAppService";E={$_.tags -contains "AppServiceIntegratedApp"}}, `
    @{N="EntraRecommendedStale";E={$sps_recommemded_stale_hash[$_.appid].AddedDateTime}}, `
    @{N="30DSuccessfulSignInCount";E={$30daySignInCount[$_.appid].SuccessfulSignInCount}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\applications.csv -NoTypeInformation -Append

write-host "finding everything else"
$classified = (import-csv .\entra_apps.csv).id
$servicePricipals | where {$_.id -notin $classified} | `
 where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a') -and $_.appDisplayname -ne "Microsoft Assessments"}  | select `
     @{N="Type";E={if($apps_flow_hash[$_.appid].ImplicitGrant -eq $true -and $apps_flow_hash[$_.appid].RedirectUris -like "*"){"oauth2"}else{"unknown"}}},`
      Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
   @{N="EntraRecommendedStale";E={$sps_recommemded_stale_hash[$_.appid].AddedDateTime}}, `
    @{N="30DSuccessfulSignInCount";E={$30daySignInCount[$_.appid].SuccessfulSignInCount}}, `
    @{N="AzureAppService";E={$_.tags -contains "AppServiceIntegratedApp"}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\applications.csv -NoTypeInformation -Append


write-host "Complete results can be found in the downloads folder"
