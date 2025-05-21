<#
.VERSION 2021.12.1
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
This script will remove guest that have not used their accounts in x number of days.
Important its designed to work in Azure AutomationAccounts. To set up the Azure Automation Account
Review this url: https://github.com/chadmcox/Azure_Active_Directory_Scripts/blob/master/Maintenance%20Task/README.md
This is using oauth2 to authenticate, from the managedid created as part of 
the azure automation account.  Once the accounts is create appropriate permissions
will need to be provided to the account.
.Instructions
This script will remove guest that have not logged on in x number of days.
!!!This will only work with premier license
#> 
#this is the number of days a guest account has to sign in before, they are considered to be deleted.
$notsignedonindays = 120
#this is a standard theshold, only the number provided below will be returned and deleted.
$removalthreshold = 250

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
function remove-AADGuestUser{
    [cmdletbinding()]
    param($guestid)
    try{
            $uri = "https://graph.microsoft.com/beta/users/$guestid"
            Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method Delete
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
    }
}
function restore-AADGuestUser{
    [cmdletbinding()]
    param($guestid)
    Start-Sleep -Seconds 15
    try{
            $uri = "https://graph.microsoft.com/beta/directory/deleteditems/$guestid/restore"
            Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method POST -ContentType "application/json"
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
    }
}

# Get access token for Graph API
$graphApiToken = Get-GraphAPIAccessToken
# Create header for using Graph API
$graphApiHeader = @{ Authorization = "Bearer $graphApiToken" }

#this is the graph api to users
#https://docs.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-beta
$uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest' and accountEnabled eq true&`$select=id,displayName,signInActivity,userPrincipalName,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,onPremisesSyncEnabled&`$expand=memberOf"
return-AADMSGraph -Uri $uri -pv user | where {!($_.onPremisesSyncEnabled -eq $true)} | `
    where {($_.signInActivity.lastSignInDateTime -eq $null) -or ((New-TimeSpan -Start $_.signInActivity.lastSignInDateTime -end $(get-date)).TotalDays -gt $notsignedonindays)} | `
    where {($user.signInActivity.lastNonInteractiveSignInDateTime -eq $null) -or ((New-TimeSpan -Start $user.signInActivity.lastNonInteractiveSignInDateTime -end $(get-date)).TotalDays -gt $notsignedonindays)} | `
    where {$_.externalUserState -ne 'PendingAcceptance' -and ((New-TimeSpan -Start $user.createdDateTime -end $(get-date)).TotalDays -gt $notsignedonindays)} | `
    where {!($_.memberOf.groupTypes -contains "Unified")} | `
        select id,displayName,signInActivity,userPrincipalName -first $removalthreshold | foreach{
            Write-Output "Deleting - $($user.userPrincipalName) : lastSignInDateTime $($user.signInActivity.lastSuccessfulSignInDateTime)"
            #!!!!!!!!! when you are ready remove the pound / hashtag in front of the next line !!!!!!!!!!
           # remove-AADGuestUser -guestid $user.id
            #the restore is not needed
            #Write-Output "Restoring - $($user.userPrincipalName)"
            #restore-AADGuestUser -guestid $user.id
        }
