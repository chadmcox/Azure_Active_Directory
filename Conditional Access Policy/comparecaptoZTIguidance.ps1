cd "$env:USERPROFILE\downloads"

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

#export all enabled conditional access policies
$uri = "$script:graphendpoint/beta/identity/conditionalAccess/policies"
$all_conditional_access_policies = get-MSGraphRequest -uri $uri | where {$_.state -eq "enabled"}

function get-commoncapolicies{
    [cmdletbinding()] 
        param()
    #Common Identity Policies and Device Policies

    #-------------------------------------------------------------------------
    $Protection_Level = "Starting"
    $Policy = "Require MFA when sign-in risk is medium or high"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    
    #--------------------------------------------------------------------------
    
    $Policy = "Always require MFA from untrusted networks"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -gt 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block clients that do not support modern authentication"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.clientAppTypes -eq "other"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "High risk users must change password"
    $found = $null;$found = $all_conditional_access_policies | `
                where {$_.conditions.userRiskLevels -like "*high*"} |
                where {$_.conditions.applications.includeApplications -eq 'All'} | `
                where {$_.conditions.users.includeUsers -eq "All"} | `
                where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
                where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Require approved apps on mobile devices"
    $found = $null;$found = $all_conditional_access_policies | `
        where {$_.grantControls.builtInControls -contains "approvedApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -and $_.conditions.platforms.includePlatforms -contains "iOS"}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Require app protection on mobile devices"
    $found = $null;$found = $all_conditional_access_policies | `
        where {$_.grantControls.builtInControls -contains "compliantApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -and $_.conditions.platforms.includePlatforms -contains "iOS"}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Require MFA when sign-in risk is low, medium, or high"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.signInRiskLevels -like "*low*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Require compliant PCs and mobile devices for Office 365"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "No Persistent Browser and 1 Hour Session for Unmanaged Devices"
    $found = $null;$found = $all_conditional_access_policies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.devices.deviceFilter.mode -eq "include"} | `
        where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -or device.trustType -ne "ServerAD"'} | `
        where {$_.sessionControls.signInFrequency.isEnabled -eq "True"} | `
        where {$_.sessionControls.persistentBrowser.isEnabled -eq "True"}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Protection_Level = "Specialized Security"
    $Policy = "Always require MFA"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block when sign-in risk is high"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block when user risk is high"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.userRiskLevels -like "*high*"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}
function get-privcapolicies{
    [cmdletbinding()] 
        param()
    #--------------------------------------------------------------------------
    #Common Privileged User Policies
    $Policy = "Require privileged users to use compliant devices"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeUsers -eq "All" -or $_.conditions.users.includeRoles -like "*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    #is all user defined?
    $priv_found = @()
    $priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
    #if all isnt found is each privileged role defined 
    if(!($priv_found)){
        $priv_found = $found
        $critical_role_template_guids | foreach{
            if(!($found.conditions.users.includeRoles -contains $_)){
                
                $priv_found = $null
            }
        }
    }
    $found = $priv_found

    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Require privileged user to MFA"
    $Protection_Level = "Enterprise"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {($_.grantControls.builtInControls -like "*mfa*") -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    #is all user defined?
    $priv_found = @()
    $priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
        where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})} 
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

    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block privileged user if sign-in risk is low, medium or high"
    $Protection_Level = "Specialized Security"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {($_.conditions.users.includeRoles -like "*") -or ($_.conditions.users.includeUsers -eq "All")} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.signInRiskLevels -contains "high" -and $_.conditions.signInRiskLevels -contains "medium" -and$_.conditions.signInRiskLevels -contains "low"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    #is all user defined?
    $priv_found = @()
    $priv_found = $found | where {$_.conditions.users.includeUsers -eq "All"}  | `
        where {!($_.conditions.users.excludeRoles | foreach{$_ -in $critical_role_template_guids})}
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

    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block Directory Sync Role Accounts from signing in from non trusted networks"
    $Protection_Level = "Enterprise"
    $role = "d29b2b05-8046-44ba-8758-1e26182fcf32"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$role -in $_.Conditions.users.includeRoles} | `
        where {$_.Conditions.locations.IncludeLocations -eq "All"} | `
        where {$_.Conditions.locations.ExcludeLocations -eq "AllTrusted"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"}
    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}
function get-guestcapolicies{
    [cmdletbinding()] 
        param()
    #Guest policies
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Require guest to MFA for High and Medium Sign-in Risk"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.GrantControls.builtincontrols -eq "MFA"} | `
        where {$_.conditions.signInRiskLevels -contains "high" -and $_.conditions.signInRiskLevels -contains "medium"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Require guest to MFA"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.GrantControls.builtincontrols -eq "MFA"} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}

#--------------------------------------------------------------------------
#Teams Policies

function get-exchangecapolicies{
[cmdletbinding()] 
        param()
    #--------------------------------------------------------------------------
    #Exchange Polices
    $Protection_Level = "Enterprise"
    $Policy = "Block Exchange Active Sync"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.clientAppTypes -like "*exchangeActiveSync*"} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All' -or $_.conditions.applications.includeApplications -contains '00000002-0000-0ff1-ce00-000000000000'} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Exchange Online Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}
function get-sharepointcapolicies{
    [cmdletbinding()] 
            param()
    #--------------------------------------------------------------------------
    #SharePoint Policies
    $Protection_Level = "Starting"
    $Policy = "Block access to SharePoint Online from apps on unmanaged devices" 
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.clientAppTypes -eq "mobileAppsAndDesktopClients"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365') -or $_.conditions.applications.includeApplications -like "*00000003-0000-0ff1-ce00-000000000000*"} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -and $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"SharePoint Online Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    $Protection_Level = "Enterprise"
    $Policy = "Use app-enforced Restrictions for browser access to Sharepoint Online"
    $found = $null;$found = $all_conditional_access_policies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.clientAppTypes -eq "browser"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365') -or $_.conditions.applications.includeApplications -like "*00000003-0000-0ff1-ce00-000000000000*"} | `
        where {$_.sessionControls.applicationEnforcedRestrictions.isEnabled -eq "True"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"SharePoint Online Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

}
function get-md4cacapolicies{
    [cmdletbinding()] 
            param()
    #--------------------------------------------------------------------------
    #Defender Policies
    $Protection_Level = "Starting"
    $Policy = "Monitor traffic from Unmanaged Devices using monitor only app control"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -or device.trustType -ne "ServerAD"' -or $_.conditions.devices.deviceFilter.rule -eq 'device.trustType -ne "ServerAD" -or device.isCompliant -ne True'} |
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "monitorOnly"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Block download of files labeled with sensitive or classified from unmanaged devices using block downloads app control"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -or device.trustType -ne "ServerAD"' -or $_.conditions.devices.deviceFilter.rule -eq 'device.trustType -ne "ServerAD" -or device.isCompliant -ne True'} |
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "blockDownloads"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Specialized Security"
    $Policy = "Block download of files labeled classified from all devices"
    $found = $null;$found = $all_conditional_access_policies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "mcasConfigured"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}

function export-capscenerio{
    cls
    get-commoncapolicies
    get-privcapolicies
    get-guestcapolicies
    get-sharepointcapolicies
    get-exchangecapolicies
    get-md4cacapolicies
}
login-MSGraph
export-capscenerio  | export-csv .\zero_trust_policies.csv -NoTypeInformation
