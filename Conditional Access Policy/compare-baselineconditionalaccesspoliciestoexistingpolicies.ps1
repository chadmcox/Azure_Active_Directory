param($path="$env:USERPROFILE\downloads")
cd $path
#Disconnect-MgGraph
cls

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

function findadminmfa{
    $priv_found = $null
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
               write-host "Missing $($_)"
                $priv_found = $null
            }
        }
    }
    $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}

}

function findadmindevice{
    $priv_found = $null
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
    $priv_found | where {$_.conditions.users.includeRoles -notcontains "d29b2b05-8046-44ba-8758-1e26182fcf32"}
}

function run{

$scenarioName = "Require multifactor authentication for admins"
$Scenarios = "secureFoundation,zeroTrust,protectAdmins"
$description = "Require multifactor authentication for privileged administrative accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-admin-mfa"
$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require compliant or hybrid Azure AD joined device for admins"
$Scenarios = "remoteWork,protectAdmins"
$description = "Require privileged administrators to only access resources when using a compliant or hybrid Azure AD joined device."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-compliant-device-admin"

$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}


    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Securing security info registration"
$Scenarios = "secureFoundation,zeroTrust,remoteWork"
$description = "Secure when and how users register for Azure AD multifactor authentication and self-service password reset."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-registration"

$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeUsers -eq "All")} | `
    where {($_.grantControls.builtInControls -like "*mfa*") -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {$_.conditions.applications.includeUserActions -eq 'urn:user:registersecurityinfo'}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block legacy authentication"
$Scenarios = "secureFoundation,zeroTrust,remoteWork,protectAdmins"
$description = "Block legacy authentication endpoints that can be used to bypass multifactor authentication."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-block-legacy"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for all users"
$Scenarios = "secureFoundation,zeroTrust,remoteWork"
$description = "Require multifactor authentication for all user accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for guest access"
$Scenarios = "zeroTrust,remoteWork"
$description = "Require guest users perform multifactor authentication when accessing your company resources."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-policy-guest-mfa"

$found = $null;$found = $all_capolicies  | `
    where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers" -or $_.conditions.users.includeUsers -eq "All"} | `
    where {!($_.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*") -and !($_.conditions.users.excludeUsers -eq "GuestsOrExternalUsers")} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Azure management"
$Scenarios = "secureFoundation,zeroTrust,protectAdmins"
$description = "Require multifactor authentication to protect privileged access to Azure management, Windows Azure Service Management API or Azure Government Cloud Management API"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-azure-management"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for risky sign-ins"
$Scenarios = "zeroTrust,remoteWork"
$description = "Require multifactor authentication if the sign-in risk is detected to be medium or high. (Requires a Microsoft Entra ID P2 license)"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk"

        $found = $null;$found = $all_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
        where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require password change for high-risk users"
$Scenarios = "zeroTrust,remoteWork"
$description = "Require the user to change their password if the user risk is detected to be high. (Requires a Microsoft Entra ID P2 license)"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk-user"

$found = $null;$found = $all_capolicies | `
    where {$_.conditions.userRiskLevels -like "*high*"} |
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access for unknown or unsupported device platform"
$Scenarios = "zeroTrust,remoteWork"
$description = "Users will be blocked from accessing company resources when the device type is unknown or unsupported."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-policy-unknown-unsupported-device"

$found = $null;$found = $all_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -gt 1) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -gt 1)} | `
    where {$_.grantControls.builtInControls  -like "*Block*"}


    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "No persistent browser session (signInFrequency)"
$Scenarios = "zeroTrust,remoteWork"
$description = "Protect user access on unmanaged devices by preventing browser sessions from remaining signed in after the browser is closed and setting a sign-in frequency to 1 hour."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-policy-persistent-browser-session"

$found = $null;$found = $all_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.devices.deviceFilter.mode -eq "include"} | `
    where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -and device.trustType -ne "ServerAD"'} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} 
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

$scenarioName = "No persistent browser session (persistentBrowser)"
$found = $null;$found = $all_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.devices.deviceFilter.mode -eq "include"} | `
    where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -and device.trustType -ne "ServerAD"'} | `
    where {$_.sessionControls.persistentBrowser.isEnabled -eq "True"}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require approved client apps or app protection policies"
$Scenarios = "zeroTrust,remoteWork"
$description = "To prevent data loss, organizations can restrict access to approved modern auth client apps with Intune app protection policies."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-policy-approved-app-or-app-protection"

$found = $null;$found = $all_capolicies | `
        where {$_.grantControls.builtInControls -contains "approvedApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

$found = $null;$found = $all_capolicies | `
    where {$_.grantControls.builtInControls -contains "compliantApplication"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require compliant or hybrid Azure AD joined device or multifactor authentication for all users"
$Scenarios = "secureFoundation,zeroTrust"
$description = "Protect access to company resources by requiring users to use a managed device or perform multifactor authentication."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-compliant-device"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -or $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0} | `
        where {$_.grantControls.operator -eq "OR"}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Use application enforced restrictions for O365 apps"
$Scenarios = "remoteWork"
$description = "Block or limit access to O365 apps, including SharePoint Online, OneDrive, and Exchange Online content. This policy requires SharePoint admin center configuration."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-policy-app-enforced-restriction"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365') -or $_.conditions.applications.includeApplications -like "*00000003-0000-0ff1-ce00-000000000000*"} | `
        where {$_.sessionControls.applicationEnforcedRestrictions.isEnabled -eq "True"} | `
        where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require phishing-resistant multifactor authentication for admins"
$Scenarios = "protectAdmins,emergingThreats"
$description = "Require phishing-resistant multifactor authentication for privileged administrative accounts to reduce risk of compromise and phishing attacks. This policy requires admins to have at least one phishing resistant authentication method registered."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/how-to-policy-phish-resistant-admin-mfa"

$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14 -or $_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {$_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa" -and ($_.grantControls.authenticationStrength.allowedCombinations -contains "fido2")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Microsoft admin portals"
$Scenarios = "zeroTrust,protectAdmins"
$description = "Use this to protect sign-ins to admin portals if you are unable to use the Require MFA for admins."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/how-to-policy-mfa-admin-portals"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access to Office365 apps for users with insider risk"
$Scenarios = "zeroTrust"
$description = "Configure insider risk as a condition to identify potential risky behavior (Requires a Microsoft Entra ID P2 license)."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/how-to-policy-insider-risk"
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'Office365')} | `
    where {($_.conditions.insiderRiskLevels -eq 'elevated')}| `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.grantControls.builtInControls  -like "*Block*"}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication on untrusted networks"
$Scenarios = "common"
$description = ""
$link = ""

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -gt 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require multifactor authentication for Intune device enrollments"
$Scenarios = "common"
$description = ""
$link = "https://learn.microsoft.com/en-us/mem/intune/enrollment/multi-factor-authentication?context=%2Fentra%2Fidentity%2Fconditional-access%2Fcontext%2Fconditional-access-context.json"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")}  | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.conditions.applications.includeApplications -eq 'd4ebce55-015a-49b5-a083-c84d1797ae8c' -or $_.conditions.applications.includeApplications -eq 'All'}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Require terms of use to be accepted"
$Scenarios = "common"
$description = "Organizations might want to require users to accept terms of use (ToU) before accessing certain applications in their environment."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/require-tou"
$found = $null;$found = $all_capolicies | where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.grantControls.termsOfUse | measure-object).count -gt 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "Block access by location"
$Scenarios = "common"
$description = ""
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-location"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.conditions.locations.includeLocations | measure-object).count -gt 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Legacy Authentication SHALL Be Blocked"
$Scenarios = "CISA MS AAD 2.2.1"
$description = "Block legacy authentication endpoints that can be used to bypass multifactor authentication."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-block-legacy"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA High Risk Users SHALL Be Blocked"
$Scenarios = "CISA MS AAD 3.1.1"
$description = "Users identified as high risk by Azure AD Identity Protection can be blocked from accessing the system via an Azure AD Conditional Access policy. A high-risk user will be blocked until an administrator remediates their account"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk-user"
 $found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.userRiskLevels -like "*high*"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA High Risk Sign-ins SHALL Be Blocked"
$Scenarios = "CISA MS AAD 3.1.3"
$description = "This prevents compromised accounts from accessing the tenant."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.signInRiskLevels -like "*high*"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Phishing-Resistant Multifactor Authentication SHALL Be Required for All Users"
$Scenarios = "CISA MS AAD 4.1.1"
$description = "Require multifactor authentication for all user accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa"} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Phishing-resistant MFA SHALL be required for highly privileged roless"
$Scenarios = "CISA MS AAD 4.1.6"
$description = "Require multifactor authentication for privileged administrative accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-admin-mfa"

$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14 -or $_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa" -and ($_.grantControls.authenticationStrength.allowedCombinations -contains "fido2")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Managed Devices SHOULD Be Required for Authentication"
$Scenarios = "CISA MS AAD 4.1.7"
$description = "The security risk of an adversary authenticating to the tenant from their own device is reduced by requiring a managed device to authenticate."
$link = ""
$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {!($_.grantControls.builtInControls -like "*mfa*")} | `
        where {($_.conditions.applications.includeApplications -eq 'All')} | `
        where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
        where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
        where {($_.grantControls.builtInControls -contains "compliantDevice") -or ($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA MS.AAD.3.8v1 Managed devices SHOULD be required to register MFA"
$Scenarios = "CISA MS AAD 4.1.8"
$description = "Reduce risk of an adversary using stolen user credentials and then registering their own MFA device to access the tenant by requiring a managed device provisioned and controlled by the agency to perform registration actions. This prevents the adversary from using their own unmanaged device to perform the registration."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-registration"

$found = $null;$found = $all_capolicies  | `
    where {($_.conditions.users.includeUsers -eq "All")} | `
    where {($_.grantControls.builtInControls -contains "compliantDevice") -or ($_.grantControls.builtInControls -contains "domainJoinedDevice")} | `
    where {$_.conditions.applications.includeUserActions -eq 'urn:user:registersecurityinfo'} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CISA Azure AD Connect SHOULD be restricted to originate from the IP address space of the network hosting the on-premises AD"
$Scenarios = "CISA MS AAD v.01 Appendix A."
$description = "Service accounts created in Azure AD (Directory Syncronization Account Role) to support the integration of Azure AD Connect SHOULD be restricted to originate from the IP address space of the network hosting the on-premises AD."
$link = ""

$role = "d29b2b05-8046-44ba-8758-1e26182fcf32"
$found = $null;$found = $all_capolicies  | `
    where {$role -in $_.Conditions.users.includeRoles} | `
    where {$_.Conditions.locations.IncludeLocations -eq "All"} | `
    where {$_.Conditions.locations.ExcludeLocations -eq "AllTrusted"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Ensure that an exclusionary Geographic Access Policy is considered"
$Scenarios = "CIS Microsoft Azure Foundations 1.2.2"
$description = "This is an effective way to prevent unnecessary and long-lasting exposure to international threats such as APTs"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-location"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {($_.conditions.locations.includeLocations | measure-object).count -gt 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure multifactor authentication is enabled for all users in administrative roles"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.1,CIS Microsoft 365 Foundations 5.2.2.5,CIS Microsoft Azure Foundations 1.2.3"
$description = "Require multifactor authentication for privileged administrative accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-admin-mfa"
$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Multifactor Authentication is Required for Windows Azure Service Management API"
$Scenarios = "CIS Microsoft Azure Foundations 1.2.6"
$description = "Require multifactor authentication to protect privileged access to Azure management, Windows Azure Service Management API or Azure Government Cloud Management API"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-azure-management"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Multifactor Authentication is Required to access Microsoft Admin Portals"
$Scenarios = "CIS Microsoft Azure Foundations 1.2.7"
$description = "Use this to protect sign-ins to admin portals if you are unable to use the Require MFA for admins."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/how-to-policy-mfa-admin-portals"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals')} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Require Multi-Factor Auth to join devices"
$Scenarios = "CIS Microsoft Azure Foundations 1.21"
$description = "Multi-factor authentication is recommended when adding devices to Microsoft Entra ID."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/how-to-policy-mfa-device-register-join"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {($_.conditions.applications.includeUserActions -eq 'urn:user:registerdevice')}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure multifactor authentication is enabled for all users"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.2,CIS Microsoft Azure Foundations 1.2.4"
$description = "Require multifactor authentication for all user accounts to reduce risk of compromise."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
    where {!($_.conditions.signInRiskLevels -like "*")} | `
    where {!($_.conditions.userRiskLevels -like "*")} | `
    where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Ensure Sign-in frequency is enabled and browser sessions are not persistent for Administrative users"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.4"
$description = "Forcing a time out for MFA will help ensure that sessions are not kept alive for an indefinite period of time, ensuring that browser sessions are not persistent will help in prevention of drive-by attacks in web browsers, this also prevents creation and saving of session cookies leaving nothing for an attacker to take."
$link = ""

$found = $null;$found = $all_capolicies | where {($_.conditions.users.includeRoles| measure-object).count -ge 14} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.sessionControls.persistentBrowser.isEnabled -eq "True"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} 

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Enable Conditional Access policies to block legacy authentication"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.3"
$description = "Legacy authentication protocols do not support multi-factor authentication. These protocols are often used by attackers because of this deficiency. Blocking legacy authentication makes it harder for attackers to gain access."
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-block-legacy"

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.clientAppTypes -eq "other"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------

$scenarioName = "CIS Ensure Microsoft Admin Portals access is limited to administrative roles"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.8"
$description = "By default, users can sign into the various portals but are restricted by what they can view. Blocking sign-in to Microsoft Admin Portals enhances security of sensitive data by restricting access to privileged users."
$link = ""

$found = $null;$found = $all_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
    where {($_.conditions.users.excludeRoles | measure-object).count -ge 14} | `
    where {$_.grantControls.builtInControls  -like "*Block*"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.conditions.applications.includeApplications -eq 'MicrosoftAdminPortals'} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Enable Entra Identity Protection sign-in risk based conditional access policies"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.7,CIS Microsoft Azure Foundations 1.21"
$description = "Require multifactor authentication if the sign-in risk is detected to be medium or high. (Requires a Microsoft Entra ID P2 license)"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk"

    $found = $null;$found = $all_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
        where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

#--------------------------------------------------------------------------
$scenarioName = "CIS Enable Entra Identity Protection user risk based conditional access policies"
$Scenarios = "CIS Microsoft 365 Foundations 5.2.2.6"
$description = "Require the user to change their password if the user risk is detected to be high. (Requires a Microsoft Entra ID P2 license)"
$link = "https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-risk-user"
$found = $null;$found = $all_capolicies | `
    where {$_.conditions.userRiskLevels -like "*high*"} |
    where {$_.conditions.applications.includeApplications -eq 'All'} | `
    where {$_.conditions.users.includeUsers -eq "All"} | `
    where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
    where {($_.conditions.platforms.deviceFilter | measure-object).count -eq 0} | `
    where {(($_.conditions.platforms.includePlatforms | measure-object).count -eq 0) -or (($_.conditions.platforms.includePlatforms -contains "all") -and ($_.conditions.platforms.excludePlatforms | measure-object).count -le 1)} | `
    where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
    where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    write-host "Comparing - $scenarioName"; $scenarioName | select @{n='scenarioName';e={$_}}, @{n='Scenarios';e={$Scenarios}},@{n='Description';e={$Description}},@{n='Link';e={$link}}, @{n='Policy Found';e={($($found).DisplayName -join(" | "))}}

}

$report = "compare_against_common_conditional_access_policy_report.csv"
Write-host "Finished - Report is $report"
run | export-csv ".\$report" -NoTypeInformation

write-host "results are here $path"
