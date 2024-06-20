param($path="$env:USERPROFILE\downloads")
cd $path

function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Policy.Read.All" -Environment $mg_env.name
}
function get-MSGraphRequest{
    [cmdletbinding()] 
        param($uri)
        
        do{$results = $null
            for($i=0; $i -le 3; $i++){
                try{
                    $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
                    break
                }catch{#if this fails it is going to try to authenticate again and rerun query
                    if(($_.Exception.response.statuscode -eq "TooManyRequests") -or ($_.Exception.Response.StatusCode.value__ -eq 429)){
                        #if this hits up against to many request response throwing in the timer to wait the number of seconds recommended in the response.
                        write-host "Error: $($_.Exception.response.statuscode), trying again $i of 3, waiting for $($_.Exception.response.headers.RetryAfter.Delta.seconds) seconds"
                        Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                    }else{
                        write-host "Error: $($_.Exception.response.statuscode)" -ForegroundColor Yellow
                        "Error: $($_.Exception.Response.StatusCode.value__)"| Add-Content $errorlogfile
                        "Error: $($_.Exception.response.statuscode)"| Add-Content $errorlogfile
                        "Error: $($_.Exception.response.RequestMessage.RequestUri.OriginalString)"| Add-Content $errorlogfile
                        $script:script_errors_found += 1
                    }
                }
            }
            if($results){
            if($results | get-member | where name -eq "value"){
                $results.value
            }else{
                $results
            }}
            $uri=$null;$uri = $Results.'@odata.nextlink'
        }until ($uri -eq $null)
}

$critical_role_template_guids = @("62e90394-69f5-4237-9190-012177145e10", ` #Company Administrator / Global Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814", ` #Privileged Role Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d", ` #Security Administrator
    "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", ` #Application Administrator
    "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", ` #Privileged Authentication Administrator
    "158c047a-c907-4556-b7ef-446551a6b5f7", ` #Cloud Application Administrator
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", ` #Conditional Access Administrator
    "c4e39bd9-1100-46d3-8c65-fb160da0071f", ` #Authentication Administrator
    "29232cdf-9323-42fd-ade2-1d097af3e4de", ` #Exchange Administrator
    "8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2", ` #Hybrid Identity Administrator
    "966707d0-3269-4727-9be2-8c3a10f19b9d", ` #Password Administrator
    "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", ` #SharePoint Administrator
    "fe930be7-5e62-47db-91af-98c3a49a38b1", ` #User Administrator
    "729827e3-9c14-49f7-bb1b-9608f156bbb8") #Helpdesk Administrator

#login
login-MSGraph
#export all enabled conditional access policies
$uri = "$script:graphendpoint/beta/identity/conditionalAccess/policies"

$all_capolicies = get-MSGraphRequest -uri $uri

$scenarioName = "Require multifactor authentication for admins"
$Scenarios = "secureFoundation,zeroTrust,protectAdmins"

$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.builtInControls -like "*mfa*") -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice") -and !($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
#is all user defined?
#$priv_found = @()
#$priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
#    where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
#if all isnt found is each privileged role defined 
if(!($priv_found)){
    $priv_found = $found
    $critical_role_template_guids | foreach{
        if(!($found.conditions.users.includeRoles -contains $_)){
               
            $priv_found = $null
        }
    }
}
$found = $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require compliant or hybrid Azure AD joined device for admins"
$Scenarios = "remoteWork,protectAdmins"
$Policy = "Require privileged role member to use compliant device"
$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
    where {!($_.grantControls.builtInControls -like "*mfa*")} | `
    where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
#is all user defined?
$priv_found = @()
#$priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
#    where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})}
#if all isnt found is each privileged role defined 
if(!($priv_found)){
    $priv_found = $found
    $critical_role_template_guids | foreach{
        if(!($found.conditions.users.includeRoles -contains $_)){
            write-host "Missing $($_)"    
            $priv_found = $null
        }
    }
}
$found = $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Securing security info registration"
$Scenarios = "secureFoundation,zeroTrust,remoteWork"

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block legacy authentication"
$Scenarios = "secureFoundation,zeroTrust,remoteWork,protectAdmins"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for all users"
$Scenarios = "secureFoundation,zeroTrust,remoteWork"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for guest access"
$Scenarios = "zeroTrust,remoteWork"
$found = $null;$found = $all_capolicies  | `
    where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.GrantControls.builtincontrols -eq "MFA"} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Azure management"
$Scenarios = "secureFoundation,zeroTrust,protectAdmins"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for risky sign-ins"
$Scenarios = "zeroTrust,remoteWork"

    $found = $null;$found = $all_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require password change for high-risk users"
$Scenarios = "zeroTrust,remoteWork"
$found = $null;$found = $all_capolicies | `
    where {$_.conditions.userRiskLevels -like "*high*"} |
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access for unknown or unsupported device platform"
$Scenarios = "zeroTrust,remoteWork"

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "No persistent browser session (signInFrequency)"
$Scenarios = "zeroTrust,remoteWork"
$found = $null;$found = $all_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.devices.deviceFilter.mode -eq "include"} | `
    where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -and device.trustType -ne "ServerAD"'} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} 
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}
$scenarioName = "No persistent browser session (persistentBrowser)"
$found = $null;$found = $all_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.devices.deviceFilter.mode -eq "include"} | `
    where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -and device.trustType -ne "ServerAD"'} | `
    where {$_.sessionControls.persistentBrowser.isEnabled -eq "True"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}
#--------------------------------------------------------------------------
$scenarioName = "Require approved client apps or app protection policies"
$Scenarios = "zeroTrust,remoteWork"

$found = $null;$found = $all_capolicies | `
        where {$_.grantControls.builtInControls -contains "approvedApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

$found = $null;$found = $all_capolicies | `
    where {$_.grantControls.builtInControls -contains "compliantApplication"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require compliant or hybrid Azure AD joined device or multifactor authentication for all users"
$Scenarios = "secureFoundation,zeroTrust"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -or $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Use application enforced restrictions for O365 apps"
$Scenarios = "remoteWork"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.clientAppTypes -eq "browser"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365') -or $_.conditions.applications.includeApplications -like "*00000003-0000-0ff1-ce00-000000000000*"} | `
        where {$_.sessionControls.applicationEnforcedRestrictions.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require phishing-resistant multifactor authentication for admins"
$Scenarios = "protectAdmins,emergingThreats"
$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -and ($_.grantControls.authenticationStrength.allowedCombinations -contains "fido2")} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice") -and !($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
#is all user defined?
#$priv_found = @()
#$priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
#    where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
#if all isnt found is each privileged role defined 
if(!($priv_found)){
    $priv_found = $found
    $critical_role_template_guids | foreach{
        if(!($found.conditions.users.includeRoles -contains $_)){
               
            $priv_found = $null
        }
    }
}
$found = $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Microsoft admin portals"
$Scenarios = "zeroTrust,protectAdmins"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access to Office365 apps for users with insider risk"
$Scenarios = "zeroTrust"

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication on untrusted networks"
$Scenarios = "common"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -gt 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Intune device enrollments"
$Scenarios = "common"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")}  | `
    where {$_.conditions.applications.includeApplications -eq 'd4ebce55-015a-49b5-a083-c84d1797ae8c'}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require terms of use to be accepted"
$Scenarios = "common"
$found = $null;$found = $all_capolicies | where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.termsOfUse | measure-object).count -gt 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access by location"
$Scenarios = "common"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.conditions.locations.includeLocations | measure-object).count -gt 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Legacy Authentication SHALL Be Blocked"
$Scenarios = "CISA MS AAD 2.2.1"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA High Risk Users SHALL Be Blocked"
$Scenarios = "CISA MS AAD 3.1.1"
 $found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.userRiskLevels -like "*high*"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA High Risk Sign-ins SHALL Be Blocked"
$Scenarios = "CISA MS AAD 3.1.3"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.signInRiskLevels -like "*high*"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Phishing-Resistant Multifactor Authentication SHALL Be Required for All Users"
$Scenarios = "CISA MS AAD 4.1.1"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Phishing-resistant MFA SHALL be required for highly privileged roless"
$Scenarios = "CISA MS AAD 4.1.6"
$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.builtInControls -like "*mfa*") -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice") -and !($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
#is all user defined?
#$priv_found = @()
#$priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
#    where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
#if all isnt found is each privileged role defined 
if(!($priv_found)){
    $priv_found = $found
    $critical_role_template_guids | foreach{
        if(!($found.conditions.users.includeRoles -contains $_)){
               
            $priv_found = $null
        }
    }
}
$found = $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Managed Devices SHOULD Be Required for Authentication"
$Scenarios = "CISA MS AAD 4.1.7"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {!($_.grantControls.builtInControls -like "*mfa*")} | `
        where {($_.conditions.applications.includeApplications -eq 'All')} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA MS.AAD.3.8v1 Managed devices SHOULD be required to register MFA"
$Scenarios = "CISA MS AAD Appendix A."

#--------------------------------------------------------------------------
$scenarioName = "CISA Azure AD Connect SHOULD be restricted to originate from the IP address space of the network hosting the on-premises AD"
$Scenarios = "CISA MS AAD Appendix A."
$role = "d29b2b05-8046-44ba-8758-1e26182fcf32"
$found = $null;$found = $all_capolicies  | `
    where {$role -in $_.Conditions.users.includeRoles} | `
    where {$_.Conditions.locations.IncludeLocations -eq "All"} | `
    where {$_.Conditions.locations.ExcludeLocations -eq "AllTrusted"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Ensure that an exclusionary Geographic Access Policy is considered"
$Scenarios = "CIS Microsoft Azure Foundations 1.2.2"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.conditions.locations.includeLocations | measure-object).count -gt 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure multifactor authentication is enabled for all users in administrative roles"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.1,CIS Microsoft 365 Foundations 5.2.2.5,CIS Microsoft Azure Foundations 1.2.3"
$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.builtInControls -like "*mfa*") -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice") -and !($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
#is all user defined?
#$priv_found = @()
#$priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
#    where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
#if all isnt found is each privileged role defined 
if(!($priv_found)){
    $priv_found = $found
    $critical_role_template_guids | foreach{
        if(!($found.conditions.users.includeRoles -contains $_)){
               
            $priv_found = $null
        }
    }
}
$found = $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Multifactor Authentication is Required for Windows Azure Service Management API"
$Scenarios = "CIS Microsoft Azure Foundations 1.26"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Multifactor Authentication is Required to access Microsoft Admin Portals"
$Scenarios = "CIS Microsoft Azure Foundations 1.27"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Require Multi-Factor Auth to join devices"
$Scenarios = "CIS Microsoft Azure Foundations 1.21"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")}  | `
    where {($_.conditions.applications.includeUserActions -eq 'urn:user:registerdevice')}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure multifactor authentication is enabled for all users"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.2,CIS Microsoft Azure Foundations 1.2.4"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Sign-in frequency is enabled and browser sessions are not persistent for Administrative users"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.4"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")}  | `
    where {($_.conditions.applications.includeUserActions -eq 'urn:user:registerdevice')}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Enable Conditional Access policies to block legacy authentication"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.3"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Ensure Microsoft Admin Portals access is limited to administrative roles"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.8"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.users.excludeRoles| measure-object).count -ge 14} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'MicrosoftAdminPortals'} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Enable Entra Identity Protection sign-in risk based conditional access policies"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.7,CIS Microsoft Azure Foundations 1.21"

    $found = $null;$found = $all_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Enable Entra Identity Protection user risk based conditional access policies"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.6"
$found = $null;$found = $all_capolicies | `
    where {$_.conditions.userRiskLevels -like "*high*"} |
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
$scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}
