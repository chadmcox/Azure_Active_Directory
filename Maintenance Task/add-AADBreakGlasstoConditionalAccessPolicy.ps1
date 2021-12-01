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
This runbook script looks for the guids of two accounts in the exclusion users for
every conditional access policy.  if it finds any missing, it will be added.

Important its designed to work in Azure AutomationAccounts. To set up the Azure Automation Account
Review this url: https://github.com/chadmcox/Azure_Active_Directory_Scripts/blob/master/Maintenance%20Task/README.md

This is using oauth2 to authenticate, from the managedid created as part of 
the azure automation account.  Once the accounts is create appropriate permissions
will need to be provided to the account.

.Instructions
update the $breakglass_accounts with the guids from the breakglass accounts in the tenants.
#> 
#these must be updated with the breakglass account guids.
$breakglass_accounts = "948b11fc-5fc4-45dd-91ac-97e38a16372a","d18d12aa-9a08-4d9d-9ffc-67995670d0c0"

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

function update-AADMSGraphCAPExclusion{
    [cmdletbinding()]
    param($capid,$missingID)
    #this function adds user objectid's to conditional access policy exclusion
    #This builds the body that has to be sent to msgraph for the patch
    $body = @"
{
    "conditions": {
        "users": {
            "excludeUsers": [
                "$missingID"
            ]
        }
    }
}
"@
    try{
        $uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$capid"
        Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method PATCH -ContentType "application/json" -body $body
    }catch{Write-Output "$($_.Exception.Response.StatusCode)"}
    
}
#useful Configure Conditional Access policies using the Microsoft Graph API
# https://github.com/Azure-Samples/azure-ad-conditional-access-apis/tree/main/01-configure/graphapi

# Get access token for Graph API
$graphApiToken = Get-GraphAPIAccessToken
# Create header for using Graph API
$graphApiHeader = @{ Authorization = "Bearer $graphApiToken" }

#this is the graph api to conditional access policies
#https://docs.microsoft.com/en-us/graph/api/resources/conditionalaccesspolicy?view=graph-rest-beta
$uri = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies"
return-AADMSGraph -Uri $uri -pv cap | select -ExpandProperty conditions | select -ExpandProperty Users -pv users  | foreach{
    #flush the variable and then look for breakglass objects missing and store in variable
    $missing=$null;$missing = $breakglass_accounts | where {$_ -notin $users.excludeUsers}

    if($cap.Conditions.clientApplications.includeServicePrincipals.count -gt 0){
        Write-Output "Skipping: $($cap.displayName) because it is a service principal/workload conditional access policy"
    }elseif($missing -ne $null){
        Write-Output "Updating: $($cap.displayName) with $($missing -join(","))"
        update-AADMSGraphCAPExclusion -capid $cap.id -missingid @(($users.excludeUsers + $missing) -join("`",`""))
    }else{
        Write-Output "Skipping: $($cap.displayName) no changes needed"
    }
}
