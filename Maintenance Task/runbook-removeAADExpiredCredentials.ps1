
<#
.VERSION 2021.12.6
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
this runbook script will review all credential and will delete ones that are expired before the 
$credsexpiredforindays which means if the value is 30, it will only remove creds that have been 
expired for 30 days.
.Instructions

#> 
#this is a standard theshold, only the number provided below will be returned and deleted.
param($removalthreshold = 3,
$credsexpiredforindays = 30)

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
                Write-Output "$($_.Exception.Response.StatusCode)"
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
function retrieve-AADSPCreds{
    [cmdletbinding()]
    param()
    Write-Output "Gathering servicePrincipals"
    $today = get-date
    try{
            $uri = "https://graph.microsoft.com/beta/servicePrincipals?`$select=displayName,id,appId,keyCredentials,passwordCredentials"
            return-AADMSGraph -uri $uri -pipelinevariable sp  | where {$sp.servicePrincipalType -ne "ManagedIdentity"} | foreach{
                $sp.keyCredentials | where {$today -gt $_.endDateTime} | select @{name='objectid';expression={$sp.id}}, @{name='objectdisplayName';expression={$sp.displayName}}, `
                @{name='objectType';expression={"ServicePrincipal"}}, @{name='id';expression={$_.keyId}}, endDateTime, @{name='credType';expression={"keyCredentials"}}
                $sp.passwordCredentials | where {$today -gt $_.endDateTime} | select @{name='objectid';expression={$sp.id}}, @{name='objectdisplayName';expression={$sp.displayName}}, `
                @{name='objectType';expression={"ServicePrincipal"}}, @{name='id';expression={$_.keyId}}, endDateTime, @{name='credType';expression={"passwordCredentials"}}
            }
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
    }
}

function retrieve-AADAPPCreds{
    [cmdletbinding()]
    param()
    Write-Output "Gathering applications"
    $today = (get-date).adddays(-$credsexpiredforindays)
    try{
            $uri = "https://graph.microsoft.com/beta/applications?`$select=displayName,id,appId,keyCredentials,passwordCredentials"
            return-AADMSGraph -uri $uri -pipelinevariable app  | foreach{
                $app.keyCredentials | where {$today -gt $_.endDateTime} | select @{name='objectid';expression={$app.id}}, @{name='objectdisplayName';expression={$app.displayName}}, `
                @{name='objectType';expression={"application"}}, @{name='id';expression={$_.keyId}}, endDateTime, @{name='credType';expression={"keyCredentials"}}
                $app.passwordCredentials | where {$today -gt $_.endDateTime} | select @{name='objectid';expression={$app.id}}, @{name='objectdisplayName';expression={$app.displayName}}, `
                @{name='objectType';expression={"application"}}, @{name='id';expression={$_.keyId}}, endDateTime, @{name='credType';expression={"passwordCredentials"}}
            }
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
    }
}

function remove-AADCred{
    [cmdletbinding()]
    param($id,$keyid,$objectType,$credType,$endDateTime)
    Write-Output "$id - $objecttype - $keyid - $credtype"
    $body = @"
{
    "keyId": "$keyid"
}
"@
    try{
        if($objectType -eq "application" -and $credtype -eq "passwordCredentials"){
            #Write-Output "application - passwordCredentials"
            $uri = "https://graph.microsoft.com/beta/applications/$id/removePassword"
        }elseif(credType -eq "application" -and $credtype -eq "keyCredentials"){
            #Write-Output "application - keyCredentials"
            $uri = "https://graph.microsoft.com/beta/applications/$id/removeKey"
        }elseif($objectType -eq "ServicePrincipal" -and $credtype -eq "passwordCredentials"){
            #Write-Output "ServicePrincipal - passwordCredentials"
            $uri = "https://graph.microsoft.com/beta/servicePrincipals/$id/removePassword"
        }elseif($objectType -eq "ServicePrincipal" -and $credtype -eq "keyCredentials"){
            #Write-Output "ServicePrincipal - keyCredentials"
            $uri = "https://graph.microsoft.com/beta/servicePrincipals/$id/removeKey"
        }
        #Write-Output "$uri"
        #Write-Output "$body"
        Invoke-RestMethod -Uri $Uri -Headers $graphApiHeader -Method POST -body $body -ContentType "application/json"
        
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
        #$error[0]
    }
}

function retrieve-AADExpiredCreds{
    [cmdletbinding()]
    param()
    retrieve-AADAPPCreds 
    retrieve-AADSPCreds 
}

# Get access token for Graph API
$graphApiToken = Get-GraphAPIAccessToken
# Create header for using Graph API
$graphApiHeader = @{ Authorization = "Bearer $graphApiToken" }

retrieve-AADExpiredCreds -pipelinevariable cred | select -first $removalthreshold | foreach{
    remove-AADCred -id $cred.objectid -keyid $cred.id -objectType $cred.objecttype -credType $cred.credType -endDateTime $cred.endDateTime
}

