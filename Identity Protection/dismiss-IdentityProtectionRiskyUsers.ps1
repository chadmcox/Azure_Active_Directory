#Requires -module Microsoft.Graph.Authentication
<#
.GUID 18c37c40-e24d-4534-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk

.Description
This script will go out and retrieve all risky users from PIM
and will dismiss them based on critieria
The default critiria is older than 120 days and are low and medium risk.

#>
param($resultslocation = "$env:USERPROFILE\Downloads",
$riskolderthanindays = 30, #in days
$risklevel = @("low","medium","high"), #low, medium, high
$log = ".\dismissedriskyuser.log")

Connect-MgGraph -Scopes "Policy.Read.All","Reports.Read.All","AuditLog.Read.All","Directory.Read.All","User.Read.All", `
    "IdentityRiskEvent.Read.All","IdentityRiskyUser.ReadWrite.All"
cd $resultslocation
function getAADRiskyUsers{
    [cmdletbinding()] 
    param()
    $uri = "https://graph.microsoft.com/beta/riskyUsers?`$filter=riskState eq 'atRisk'"
    do{$results = $null
        for($i=0; $i -le 3; $i++){
            try{
                $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
                break
            }catch{#if this fails it is going to try to authenticate again and rerun query
                if(($_.Exception.response.statuscode -eq "TooManyRequests") -or ($_.Exception.Response.StatusCode.value__ -eq 429)){
                    #if this hits up against to many request response throwing in the timer to wait the number of seconds recommended in the response.
                    write-host "Error: $($_.Exception.response.statuscode), trying again $i of 3"
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}
function dismissRiskyUsers{
    [cmdletbinding()] 
    param($user)
    $userid = $user.id
    #https://docs.microsoft.com/en-us/graph/api/riskyusers-dismiss?view=graph-rest-beta&tabs=http
    $uri = "https://graph.microsoft.com/beta/riskyUsers/dismiss"
    $body = @"
{
    "userIds": [
    "$userid"
    ]
}
"@
    try{
        Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body
        "$((Get-Date).toString("yyyy-dd-MM-HH:mm:ss:fff tt")) Success, Dismissed: $($user.userPrincipalName)" | Add-Content $log

    }catch{
        Write-host "Error $($_.Exception.response.statuscode)"
        "$((Get-Date).toString("yyyy-dd-MM-HH:mm:ss:fff tt")) Failed, Dismissed: $($user.userPrincipalName) - error: $($_.Exception.response.statuscode)" | `
            Add-Content $log
    }
}

write-host "Going to dismiss any risky user older than $riskolderthanindays"


getAADRiskyUsers -pv riskyuser | where {$_.riskState -eq "atRisk"} | where {if($_.riskLastUpdatedDateTime){((New-TimeSpan -Start $_.riskLastUpdatedDateTime -end $(get-date)).TotalDays -gt $riskolderthanindays) -and ($_.riskLevel -in $risklevel)}} | foreach{
    Write-Host "Dismissing: $($_.userPrincipalName)"
    dismissRiskyUsers -user $riskyuser
}

write-host "Log file can be found here cd $resultslocation"
