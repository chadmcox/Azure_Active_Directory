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

$translated_hash = @{}
function translate-fromgraph{
    param($guid)
    #write-host "this is the guid $guid"
    $user = (Get-MgBetaDirectoryObjectById -Ids $guid | select -ExpandProperty AdditionalProperties | convertto-json -Depth 99 | convertfrom-json).displayname
    #write-host "this is the guid $user"
    return $user
}
function transitivemember-count{
    param($guid)
    Get-MgBetaGroupTransitiveMemberCount -GroupId $guid -ConsistencyLevel "Eventual"
}

$all_capolicies | foreach {$cap="";$cap=$_
    #export excluded users 
    $cap.conditions.users.excludeUsers |  select @{n='status';e={$cap.state}},@{n='displayName';e={$cap.displayName}},@{n='Objecttype';e={"User"}}, @{n='ExcludedObject';e={(translate-fromgraph -guid $_)}}, @{n='TransitiveMemberCount';e={"0"}}
    #export excluded groups
    $cap.conditions.users.excludeGroups |  select @{n='status';e={$cap.state}},@{n='displayName';e={$cap.displayName}},@{n='Objecttype';e={"Group"}},@{n='ExcludedObject';e={(translate-fromgraph -guid $_)}}, @{n='TransitiveMemberCount';e={transitivemember-count -guid $_}}
    #do guest
    if(($cap.conditions.users.excludeGuestsOrExternalUsers | measure).count -gt 0){
    $cap.conditions.users.excludeGroups |  select @{n='status';e={$cap.state}},@{n='displayName';e={$cap.displayName}},@{n='Objecttype';e={"Guest"}},@{n='ExcludedObject';e={"GuestsOrExternalUsers"}}, @{n='TransitiveMemberCount';e={$totalGuest}}
    }
} | export-csv .\conditional_access_policy_excluded_user_stats.csv -NoTypeInformation
