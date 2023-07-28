<#
.VERSION 2023.7.27
.GUID 5858348a-5111-4e17-8afe-e7f7313df7f5
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
This script will populate the sponsors attribute on guest accounts.
logs go back 30 days, but when this is set to reoccuring I would do a daily run of this. To set up the Azure Automation Account
Review this url: https://github.com/chadmcox/Azure_Active_Directory_Scripts/blob/master/Maintenance%20Task/README.md
This is using oauth2 to authenticate, from the managedid created as part of 
the azure automation account.  Once the accounts is create appropriate permissions
will need to be provided to the account.
.Instructions
This script will populate the sponsors attribute on guest accounts.
logs go back 30 days, but when this is set to reoccuring I would do a daily run of this.
#> 
$days_back = 1
$querydate=$(get-date (get-date).AddDays(-$days_back) -Format yyyy-MM-dd)

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

$uri = "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Invite external user' and activityDateTime gt $querydate"
Write-Output "$uri"
return-AADMSGraph | where {$_.initiatedBy.user.id} | foreach{
Write-Output "Updating Guest: $($_.targetResources.id) with a sponsor of $($_.initiatedBy.user.id)"
$body = @"
{
  "@odata.id": "https://graph.microsoft.com/beta/users/$($_.initiatedBy.user.id)"
}
"@
$uri = "https://graph.microsoft.com/beta/users/$($_.targetResources.id)"
Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method POST -ContentType "application/json" -body $body
}
