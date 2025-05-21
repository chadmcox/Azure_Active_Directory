<#
.VERSION 2022.4.21
.GUID be1af58d-ee61-4f7e-a57f-b28712ccd991
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.COMPANYNAME 
.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample Code..
.DESCRIPTION
this script will dismiss users risk after xx number of days
#> 
#this is the number of days a guest account has to accept before, they are considered to be deleted.
$riskolderthanindays = 120 #in days
#This is the levels you want to allowed to be cleared
$risklevel = @("low","medium") #low, medium, high
#this is a standard theshold, only the number provided below will be returned and deleted.
$removalthreshold = 100

$today = get-date

function Get-GraphAPIAccessToken {
    [cmdletbinding()]
    param()
    #All Credit for this goes to
    #https://www.gericke.name/managed-identity-with-azure-automation-and-graph-api/#:~:text=%20Managed%20Identity%20with%20Azure%20Automation%20and%20Graph,Enterprise%20applications%20you...%205%20Reference.%20%20More%20
    
    $resource= "?resource=https://graph.microsoft.com/"
    $url = $env:IDENTITY_ENDPOINT + $resource
    $Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER)
    $Headers.Add("Metadata", "True")
    $accessToken = Invoke-RestMethod -Uri $url -Method 'GET' -Headers $Headers
    return $accessToken.access_token
}

function return-AADMSGraph{
    [cmdletbinding()]
    param($uri)
    #this function returns all results from a graph query
    do{
        $results= $null;
        for($i=0; $i -le 3; $i++){
            try{
                $results = Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method Get -ContentType "application/json"
                break
            }catch{
                #If to many request occur, graph will return a 429 meaning TooManyRequests, it also provides a recommended retry interval
                if ($_.Exception.Response.StatusCode.value__ -eq 429){
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}
function getAADRiskyUsers{
    [cmdletbinding()] 
    param()
    $uri = "https://graph.microsoft.com/beta/riskyUsers"
    return-AADMSGraph -uri $uri
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
		Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method POST -ContentType "application/json" -body $body
        
        Write-Output "$((Get-Date).toString("yyyy-dd-MM-HH:mm:ss:fff tt")) Success, Dismissed: $($user.userPrincipalName)"

    }catch{
        Write-host "Error $($_.Exception.response.statuscode)"
        Write-Output "$((Get-Date).toString("yyyy-dd-MM-HH:mm:ss:fff tt")) Failed, Dismissed: $($user.userPrincipalName) - error: $($_.Exception.response.statuscode)" 
    }
}

# Get access token for Graph API
$graphApiToken = Get-GraphAPIAccessToken
# Create header for using Graph API
$graphApiHeader = @{ Authorization = "Bearer $graphApiToken" }

#this is the graph api to users

getAADRiskyUsers -pv riskyuser | where {$_.riskState -eq "atRisk"} | `
	where {if($_.riskLastUpdatedDateTime){
		((New-TimeSpan -Start $_.riskLastUpdatedDateTime -end $(get-date)).TotalDays -gt $riskolderthanindays) -and ($_.riskLevel -in $risklevel)
			}} | select * -first $removalthreshold | foreach{
    Write-Output "Dismissing: $($_.userPrincipalName)"
    #dismissRiskyUsers -user $riskyuser
}
