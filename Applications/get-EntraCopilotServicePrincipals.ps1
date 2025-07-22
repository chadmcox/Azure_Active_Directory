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

$servicePricipals = Get-MgBetaServicePrincipal  -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | where {$_.DisplayName -like "*(Microsoft Copilot Studio)" -or $_.displayname -like "*(Power Virtual Agents)"}

$servicePricipals  | select @{N="Type";E={$_.preferredSingleSignOnMode}}, `
    Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}
