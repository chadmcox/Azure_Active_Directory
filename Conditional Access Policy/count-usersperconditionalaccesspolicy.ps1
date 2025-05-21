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

function resolve-app{
    [cmdletbinding()] 
        param($appid)
        if($appid -match("^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$")){
            (Get-MgBetaServicePrincipal -Filter "appId eq '$appid'").displayName
        }else{
            $appid
        }
}


#login
login-MSGraph
#export all enabled conditional access policies
$uri = "$script:graphendpoint/beta/identity/conditionalAccess/policies"

$all_capolicies = get-MSGraphRequest -uri $uri
$totalUsers = Get-MgBetaUserCount -ConsistencyLevel "Eventual" -filter "AccountEnabled eq true"
$totalGuest = Get-MgBetaUserCount -ConsistencyLevel "Eventual" -filter "userType eq 'Guest'"

$all_capolicies | foreach {$cap="";$cap=$_
    $IncludedUsers = 0
    if($cap.conditions.users.includeUsers -contains "All"){
        $IncludedUsers = "$($totalUsers + $totalGuest) (All)"
    }else{
        $IncludedUsers = ($cap.conditions.users.includeUsers).count
    }
    if(($cap.conditions.users.includeGroups | measure).count -gt 0){
        $cap.conditions.users.includeGroups | foreach{
         $IncludedUsers += Get-MgBetaGroupTransitiveMemberCount -GroupId $_ -ConsistencyLevel "Eventual"
        }
    }
    if(($cap.conditions.users.includeRoles | measure).count -gt 0){
        $cap.conditions.users.includeRoles | foreach{
           $IncludedUsers +=  (Get-MgBetaRoleManagementDirectoryRoleDefinition -filter "TemplateId eq '$($_)'" | select * | foreach{
                Get-MgBetaRoleManagementDirectoryRoleAssignment -filter "RoleDefinitionId eq '$($_.id)'"
            } | select PrincipalId -Unique).count
        }
    }
    if(($cap.conditions.users.includeGuestsOrExternalUsers | measure).count -gt 0){
        $IncludedUsers += $totalGuest
    }
        $ExcludedUsers = 0
    if($cap.conditions.users.excludeUsers -contains "All"){
        $ExcludedUsers = $totalUsers
    }else{
        $ExcludedUsers = ($cap.conditions.users.excludeUsers).count
    }
    if(($cap.conditions.users.excludeGroups | measure).count -gt 0){
        $cap.conditions.users.excludeGroups | foreach{
         $ExcludedUsers += Get-MgBetaGroupTransitiveMemberCount -GroupId $_ -ConsistencyLevel "Eventual"
        }
    }
    if(($cap.conditions.users.excludeRoles | measure).count -gt 0){
        $cap.conditions.users.excludeRoles | foreach{
           $ExcludedUsers +=  (Get-MgBetaRoleManagementDirectoryRoleDefinition -filter "TemplateId eq '$($_)'" | select * | foreach{
                Get-MgBetaRoleManagementDirectoryRoleAssignment -filter "RoleDefinitionId eq '$($_.id)'"
            } | select PrincipalId -Unique).count
        }
    }
    if(($cap.conditions.users.excludeGuestsOrExternalUsers | measure).count -gt 0){
        $ExcludedUsers += $totalGuest
    }
    $cap | select @{n='ConditionalAccessPolicyName';e={$_.displayName}}, `
        state, @{n='TotalEnabledUsers';e={"Users: $totalUsers Guest: $totalGuest"}}, `
        @{n='TargetedUserCount';e={$IncludedUsers}}, `
        @{n='ExcludedUserCount';e={$ExcludedUsers}}, `
        @{n='GrantControl';e={($cap.grantControls.builtInControls -join(" $($cap.grantControls.operator) "))}}, `
        @{n='included: Applications';e={($_.conditions.applications.includeApplications | foreach{resolve-app -appid $_}) -join(";")}}, `
        @{n='excluded: Applications';e={($_.conditions.applications.excludeApplications | foreach{resolve-app -appid $_}) -join(";")}}, `
        @{n='includePlatforms';e={if($_.conditions.platforms.includePlatforms -eq 'All'){'All'}else{$(($_.conditions.platforms.includePlatforms) -join(";"))}}}, `
        @{n='excludePlatforms';e={if($_.conditions.platforms.excludePlatforms -eq 'All'){'All'}else{$(($_.conditions.platforms.excludePlatforms) -join(";"))}}}, `
        @{n='includeLocations';e={if($_.conditions.locations.includeLocations -eq 'All'){'All'}else{($_.conditions.locations.includeLocations | measure).count}}}, `
        @{n='excludeLocations';e={if($_.conditions.locations.excludeLocations -eq 'AllTrusted'){'AllTrusted'}else{($_.conditions.locations.excludeLocations | measure).count}}}, `
        @{n='clientAppTypes';e={if($_.conditions.clientAppTypes -eq 'all'){'All'}else{$(($_.conditions.clientAppTypes) -join(";"))}}}, `
        @{n='deviceFilter';e={if($_.conditions.devices.deviceFilter){$true}else{}}}, `
        @{n='disableResilienceDefaults';e={$_.grantControls.sessionControls.disableResilienceDefaults}}, `
        @{n='applicationEnforcedRestrictions';e={$_.sessionControls.applicationEnforcedRestrictions.isenabled}}, `
        @{n='cloudAppSecurity';e={$_.sessionControls.cloudAppSecurity.cloudAppSecurityType}}, `
        @{n='continuousAccessEvaluation';e={$_.sessionControls.continuousAccessEvaluation}}, `
        @{n='secureSignInSession';e={$_.sessionControls.secureSignInSession}}, `
        @{n='signInFrequency';e={if($_.sessionControls.signInFrequency.isenabled){"$($_.sessionControls.signInFrequency.isenabled) / $($_.sessionControls.signInFrequency.frequencyInterval)"}}}, `
        @{n='persistentBrowser';e={$_.sessionControls.persistentBrowser.mode}}, `
        TokenProtection
    
} | export-csv .\usercountscopedforeachconditionalaccesspolicy.csv -NoTypeInformation

write-host "results found here:  $path"
