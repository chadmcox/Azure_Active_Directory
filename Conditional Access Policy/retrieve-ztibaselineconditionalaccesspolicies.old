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



function get-commoncapolicies{
    [cmdletbinding()] 
        param()
    #Common Identity Policies and Device Policies

    #-------------------------------------------------------------------------
    $Protection_Level = "Starting"
    $Policy = "Require MFA when sign-in risk is medium or high"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.conditions.signInRiskLevels -like "*medium*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    
    #--------------------------------------------------------------------------
    
    $Policy = "Always require MFA from untrusted networks"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -gt 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block clients that do not support modern authentication"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.clientAppTypes -eq "other"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}

    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "High risk users must change password"
    $found = $null;$found = $all_enabled_capolicies | `
                where {$_.conditions.userRiskLevels -like "*high*"} |
                where {$_.conditions.applications.includeApplications -eq 'All'} | `
                where {$_.conditions.users.includeUsers -eq "All"} | `
                where {$_.grantControls.builtInControls -like "*passwordChange*"} | `
                where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Require approved apps on mobile devices"
    $found = $null;$found = $all_enabled_capolicies | `
        where {$_.grantControls.builtInControls -contains "approvedApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Require app protection on mobile devices"
    $found = $null;$found = $all_enabled_capolicies | `
        where {$_.grantControls.builtInControls -contains "compliantApplication"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.platforms.includePlatforms -contains "android" -or $_.conditions.platforms.includePlatforms -contains "iOS"}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Require MFA when sign-in risk is low, medium, or high"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.signInRiskLevels -like "*high*"} | `
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
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365')} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "No Persistent Browser and 1 Hour Session for Unmanaged Devices"
    $found = $null;$found = $all_enabled_capolicies | where {($_.conditions.applications.includeApplications -eq 'All')} | `
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
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Block when sign-in risk is high"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.signInRiskLevels -like "*high*"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block when user risk is high"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.conditions.userRiskLevels -like "*high*"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    
    #--------------------------------------------------------------------------
    $Policy = "Require Compliant Device for All Apps"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {!($_.grantControls.builtInControls -like "*mfa*")} | `
        where {($_.conditions.applications.includeApplications -eq 'All')} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Device Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    $Protection_Level = "Starting"
    $Policy = "Always require MFA or Trusted Device or Compliant Device from untrusted networks"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -or $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -gt 0}
    $Protection_Level | select @{n='Section';e={"Generic Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Always require MFA or Trusted Device or Compliant Device"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -or $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Generic Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Require MFA for Microsoft Graph PowerShell and Explorer"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains 'de8bc8b5-d9f9-48b1-a8ad-b748da725064' -and $_.conditions.applications.includeApplications -contains '14d82eec-204b-4c2f-b7e8-296a70dab67e')} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Policy = "Require MFA for Microsoft Azure Management"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
        where {$_.grantControls.builtInControls -like "*mfa*" -or ($_.grantControls.authenticationStrength.requirementsSatisfied -eq "mfa") -or ($_.grantControls.grantcontrols.customAuthenticationFactors -ne $null)} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {!($_.conditions.userRiskLevels -like "*")} | `
        where {!($_.grantControls.builtInControls -contains "compliantDevice")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Common Identity Policy"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}
function get-privcapolicies{
    [cmdletbinding()] 
        param()
    $priv_found = $null
    #--------------------------------------------------------------------------
    $Policy = "Require privileged role member to MFA"
    $Protection_Level = "Enterprise"
    $found = $null;$found = $all_enabled_capolicies  | `
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

    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block privileged user if sign-in risk is low, medium or high"
    $Protection_Level = "Specialized Security"
    $found = $null;$found = $all_enabled_capolicies  | `
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
    $Policy = "Require privileged role member to use compliant device"
    $Protection_Level = "Enterprise"
    $found = $null;$found = $all_enabled_capolicies  | `
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
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$role -in $_.Conditions.users.includeRoles} | `
        where {$_.Conditions.locations.IncludeLocations -eq "All"} | `
        where {$_.Conditions.locations.ExcludeLocations -eq "AllTrusted"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"}
    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block when Directory Sync Account sign in risk is low medium high"
    $Protection_Level = "Enterprise"
    $role = "d29b2b05-8046-44ba-8758-1e26182fcf32"
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$role -in $_.Conditions.users.includeRoles} | `
        where {$_.conditions.signInRiskLevels -contains "high" -and $_.conditions.signInRiskLevels -contains "medium" -and$_.conditions.signInRiskLevels -contains "low"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"}
    $Protection_Level | select @{n='Section';e={"Privileged User Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #Require privileged role member to MFA with Auth Strengths (Fido2,CBA, Microsoft Authenticator password-less)
    
}
function get-guestcapolicies{
    [cmdletbinding()] 
        param()
    #Guest policies
    #--------------------------------------------------------------------------
    $Protection_Level = "Starting"
    $Policy = "Require guest to MFA for High and Medium Sign-in Risk"
    $found = $null;$found = $all_enabled_capolicies  | `
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
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.GrantControls.builtincontrols -eq "MFA"} | `
        where {!($_.conditions.signInRiskLevels -like "*")} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Block Guest for Medium and High Sign-in Risk"
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {$_.conditions.applications.includeApplications -eq 'All'} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
        where {$_.conditions.signInRiskLevels -contains "high" -and $_.conditions.signInRiskLevels -contains "medium"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block Guest from Azure Management"
    $found = $null;$found = $all_enabled_capolicies  | `
        #where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {($_.conditions.applications.includeApplications -contains '797f4846-ba00-4fd7-ba43-dac1f8f63013')} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
         where {!($_.conditions.signInRiskLevels -contains "high")}
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block Guest from Microsoft Graph PowerShell and Graph Explorer"
    $found = $null;$found = $all_enabled_capolicies  | `
        #where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {($_.conditions.applications.includeApplications -contains 'de8bc8b5-d9f9-48b1-a8ad-b748da725064' -and $_.conditions.applications.includeApplications -contains '14d82eec-204b-4c2f-b7e8-296a70dab67e')} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
         where {!($_.conditions.signInRiskLevels -contains "high")}
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"Guest Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    #--------------------------------------------------------------------------
    $Policy = "Block Guest to unapproved Applications"
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -like "*otherExternalUser*" -or $_.conditions.users.includeUsers -eq "GuestsOrExternalUsers"} | `
        where {$_.grantControls.builtInControls  -like "*Block*"} | `
         where {!($_.conditions.signInRiskLevels -contains "high")}
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
    $found = $null;$found = $all_enabled_capolicies  | `
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
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.clientAppTypes -eq "mobileAppsAndDesktopClients"} | `
        where {($_.conditions.applications.includeApplications -eq 'All') -or ($_.conditions.applications.includeApplications -eq 'Office365') -or $_.conditions.applications.includeApplications -like "*00000003-0000-0ff1-ce00-000000000000*"} | `
        where {$_.grantControls.builtInControls -contains "compliantDevice" -and $_.grantControls.builtInControls -contains "domainJoinedDevice"} | `
        where {($_.conditions.locations.ExcludeLocations | measure-object).count -eq 0}
    $Protection_Level | select @{n='Section';e={"SharePoint Online Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}

    $Protection_Level = "Enterprise"
    $Policy = "Use app-enforced Restrictions for browser access to Sharepoint Online"
    $found = $null;$found = $all_enabled_capolicies | where {$_.conditions.users.includeUsers -eq "All"} | `
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
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -or device.trustType -ne "ServerAD"' -or $_.conditions.devices.deviceFilter.rule -eq 'device.trustType -ne "ServerAD" -or device.isCompliant -ne True'} |
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "monitorOnly"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Enterprise"
    $Policy = "Block download of files labeled with sensitive or classified from unmanaged devices using block downloads app control"
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.conditions.devices.deviceFilter.rule -eq 'device.isCompliant -ne True -or device.trustType -ne "ServerAD"' -or $_.conditions.devices.deviceFilter.rule -eq 'device.trustType -ne "ServerAD" -or device.isCompliant -ne True'} |
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "blockDownloads"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
    #--------------------------------------------------------------------------
    $Protection_Level = "Specialized Security"
    $Policy = "Block download of files labeled classified from all devices"
    $found = $null;$found = $all_enabled_capolicies  | `
        where {$_.conditions.users.includeUsers -eq "All"} | `
        where {$_.sessionControls.cloudAppSecurity.isEnabled -eq "True"} | `
        where {$_.sessionControls.cloudAppSecurity.cloudAppSecurityType -eq "mcasConfigured"}
    $Protection_Level | select @{n='Section';e={"Defender for Cloud App Policies"}},@{n='Protection Level';e={$Protection_Level}}, @{n='Policy';e={$Policy}}, `
        @{n='Applied';e={if($found){$true}else{$false}}},@{n='Policy Found';e={($found.DisplayName -join(" | "))}}
}

function export-capscenerio{
    cls
    write-host "Finding Common Policies"
    get-commoncapolicies
    write-host "Finding Privileged User Policies"
    get-privcapolicies
    write-host "Finding External User Policies"
    get-guestcapolicies
    write-host "Finding SharePoint Online Policies"
    get-sharepointcapolicies
    write-host "Finding Exchange Online Policies"
    get-exchangecapolicies
    write-host "Finding Defender for Cloud App Policies"
    get-md4cacapolicies
}

#login
login-MSGraph
#export all enabled conditional access policies
$uri = "$script:graphendpoint/beta/identity/conditionalAccess/policies"

$all_capolicies = get-MSGraphRequest -uri $uri
$all_enabled_capolicies = $all_capolicies | where {$_.state -eq "enabled"}

#this is used to add prefix to file name
$tenant = (get-mgdomain  | where isdefault -eq $true).id
#run the function that runes each individual functions
export-capscenerio | sort section, 'protection level'  | export-csv ".\$($tenant)_zero_trust_policies.csv" -NoTypeInformation


function findobject{
    [cmdletbinding()] 
    param($objid,[switch]$isrole,[switch]$isapp)
    if(!($script:already_enumerated.containskey($objid))){
        if($isapp){
            Get-MgServicePrincipal -Filter "appId eq '$objid'" | foreach{
                $script:already_enumerated.add($_.appid,$_.DisplayName)
            }
        }
        if(!($isrole)){
            Get-MgDirectoryObject -DirectoryObjectId $objid | select id -ExpandProperty AdditionalProperties | `
                convertto-json | convertfrom-json | select id, @{n='Name';e={if($_.userprincipalname){$_.userprincipalname}else{$_.displayname}}} | foreach{
                $script:already_enumerated.add($_.Id,$_.name)
            }
        }elseif($isrole){
            Get-MgDirectoryRole -filter "RoleTemplateId eq '$objid'" | select RoleTemplateId, displayname | foreach{
                $script:already_enumerated.add($_.RoleTemplateId,$_.displayname)
            }
        } 
    }
        if($script:already_enumerated.containskey($objid)){
            $script:already_enumerated[$objid]
        }else{
            $objid
        }

}

function enumerateincludedusers{
    [cmdletbinding()] 
    param($cap)
    $foundobjects = @()
    if($cap.conditions.users.includeUsers -eq 'All'){
        return 'All'
    }elseif(($cap.conditions.users.includeUsers | measure).count -gt 0){
        $foundobjects = $_.conditions.users.includeUsers | foreach{
            findobject -objid $_
        }
    }
    if(($cap.conditions.users.includeGuestsOrExternalUsers | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -split(",")
    }
    if(($cap.conditions.users.includeRoles | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.includeRoles | foreach{
            findobject -objid $_ -isrole
        }
    }
    if(($cap.conditions.users.includeGroups | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.includeGroups | foreach{
            findobject -objid $_
        }
    }
    if(($cap.conditions.clientApplications.includeServicePrincipals | measure).count -gt 0){
        $foundobjects += $cap.conditions.clientApplications.includeServicePrincipals | foreach{
            findobject -objid $_
        }
    }
     ($foundobjects -join(";")).Replace("Administrator","Admins.")
}
function enumerateexcludedusers{
    [cmdletbinding()] 
    param($cap)
    $foundobjects = @()
    if($cap.conditions.users.excludeUsers -eq 'All'){
        return 'All'
    }elseif(($cap.conditions.users.excludeUsers | measure).count -gt 0){
        $foundobjects = $cap.conditions.users.excludeUsers | foreach{
            findobject -objid $_
        }
    }
    if(($cap.conditions.users.excludeGuestsOrExternalUsers | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -split(",")
    }
    if(($cap.conditions.users.excludeRoles | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.excludeRoles | foreach{
            findobject -objid $_ -isrole
        }
    }
    if(($cap.conditions.users.excludeGroups | measure).count -gt 0){
        $foundobjects += $cap.conditions.users.excludeGroups | foreach{
            findobject -objid $_
        }
    }
    if(($cap.conditions.clientApplications.excludeServicePrincipals | measure).count -gt 0){
        $foundobjects += $cap.conditions.clientApplications.excludeServicePrincipals | foreach{
            findobject -objid $_
        }
    }
     ($foundobjects -join(";")).Replace("Administrator","Admins.")
}


$script:already_enumerated = @{}
$script:already_enumerated.add("All","All")
$script:already_enumerated.add("Office365","Office365")
$script:already_enumerated.add("GuestsOrExternalUsers","GuestsOrExternalUsers")
$script:already_enumerated.add("None","None")
$script:already_enumerated.add("ServicePrincipalsInMyTenant","ServicePrincipalsInMyTenant")

write-host "Creating reports"
$all_capolicies | foreach{
    $_ | select displayName, state, `
        @{n='included: Users,Guest or Roles';e={enumerateincludedusers -cap $_}}, `
        @{n='excluded: Users,Guest or Roles';e={enumerateexcludedusers -cap $_}}, `
        @{n='included: Applications';e={($_.conditions.applications.includeApplications | foreach{findobject -objid $_ -isapp}) -join(";")}}, `
        @{n='excluded: Applications';e={($_.conditions.applications.excludeApplications | foreach{findobject -objid $_ -isapp}) -join(";")}}, `
        @{n='includeUserActions';e={$_.conditions.applications.includeUserActions}}, `
        @{n='userRiskLevels';e={$(($_.conditions.userRiskLevels) -join(";"))}}, `
        @{n='signInRiskLevels';e={$(($_.conditions.signInRiskLevels) -join(";"))}}, `
        @{n='includePlatforms';e={if($_.conditions.platforms.includePlatforms -eq 'All'){'All'}else{$(($_.conditions.platforms.includePlatforms) -join(";"))}}}, `
        @{n='excludePlatforms';e={if($_.conditions.platforms.excludePlatforms -eq 'All'){'All'}else{$(($_.conditions.platforms.excludePlatforms) -join(";"))}}}, `
        @{n='includeLocations';e={if($_.conditions.locations.includeLocations -eq 'All'){'All'}else{($_.conditions.locations.includeLocations | measure).count}}}, `
        @{n='excludeLocations';e={if($_.conditions.locations.excludeLocations -eq 'AllTrusted'){'AllTrusted'}else{($_.conditions.locations.excludeLocations | measure).count}}}, `
        @{n='clientAppTypes';e={if($_.conditions.clientAppTypes -eq 'all'){'All'}else{$(($_.conditions.clientAppTypes) -join(";"))}}}, `
        @{n='deviceFilter';e={if($_.conditions.devices.deviceFilter){$true}else{}}}, `
        @{n='grantControls';e={$(($_.grantControls.builtInControls) -join(";"))}}, `
        #@{n='Block';e={if($_.grantControls.builtInControls -eq 'block'){$true}else{}}}, `
        #@{n='RequireMFA';e={$_.grantControls.builtInControls -contains 'MFA'}}, `
        @{n='authenticationStrength';e={$_.grantControls.authenticationStrength.requirementsSatisfied}}, `
        #@{n='RequireCompliantDevice';e={$_.grantControls.builtInControls -contains 'compliantDevice'}}, `
        #@{n='RequireDomainJoinedDevice';e={$_.grantControls.builtInControls -contains 'domainJoinedDevice'}}, `
        #@{n='RequirePasswordChange';e={if($_.grantControls.builtInControls -contains 'passwordChange'){$true}else{}}}, `
        #@{n='RequireApprovedApplication';e={$_.grantControls.builtInControls -contains 'approvedApplication'}}, `
        #@{n='RequireCompliantApplication';e={$_.grantControls.builtInControls -contains 'compliantApplication'}}, `
        @{n='disableResilienceDefaults';e={$_.grantControls.sessionControls.disableResilienceDefaults}}, `
        @{n='applicationEnforcedRestrictions';e={$_.sessionControls.applicationEnforcedRestrictions.isenabled}}, `
        @{n='cloudAppSecurity';e={$_.sessionControls.cloudAppSecurity.cloudAppSecurityType}}, `
        @{n='continuousAccessEvaluation';e={$_.sessionControls.continuousAccessEvaluation}}, `
        @{n='secureSignInSession';e={$_.sessionControls.secureSignInSession}}, `
        @{n='signInFrequency';e={if($_.sessionControls.signInFrequency.isenabled){"$($_.sessionControls.signInFrequency.isenabled) / $($_.sessionControls.signInFrequency.frequencyInterval)"}}}, `
        @{n='persistentBrowser';e={$_.sessionControls.persistentBrowser.mode}}, `
        TokenProtection

} | export-csv ".\$($tenant)_ca_policies.csv" -NoTypeInformation


write-host "Results found here: $path" -ForegroundColor Yellow
