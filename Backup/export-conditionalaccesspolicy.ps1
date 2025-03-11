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
$all_enabled_capolicies = $all_capolicies | where {$_.state -eq "enabled"}

#this is used to add prefix to file name
$tenant = (get-mgbetadomain  | where isdefault -eq $true).id



function findobject{
    [cmdletbinding()] 
    param($objid,[switch]$isrole,[switch]$isapp)
    if(!($script:already_enumerated.containskey($objid))){
        if($isapp){
            Get-MgBetaServicePrincipal -Filter "appId eq '$objid'" | foreach{
                $script:already_enumerated.add($_.appid,$_.DisplayName)
            }
        }
        if(!($isrole)){
            Get-MgBetaDirectoryObject -DirectoryObjectId $objid | select id -ExpandProperty AdditionalProperties | `
                convertto-json | convertfrom-json | select id, @{n='Name';e={if($_.userprincipalname){$_.userprincipalname}else{$_.displayname}}} | foreach{
                $script:already_enumerated.add($_.Id,$_.name)
            }
        }elseif($isrole){
            Get-MgBetaDirectoryRoleTemplate -DirectoryRoleTemplateId $objid | select Id, displayname | foreach{
                $script:already_enumerated.add($_.Id,$_.displayname)
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

} | export-csv .\conditionalaccesspolicy.csv -notypeinformation
