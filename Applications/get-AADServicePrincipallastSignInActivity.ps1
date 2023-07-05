<#PSScriptInfo
.VERSION 2023.7
.GUID 368f7248-347a-46d9-ba36-3ae42890daed
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/
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
from the use or distribution of the Sample 

.NOTE
This is a beta api make sure
https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta&tabs=http
#>
param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

function getFromMSGraph{
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
                    write-host "Error: $($_.Exception.response.statuscode), trying again $i of 3"
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }elseif(($_.Exception.response.statuscode -eq "BadRequest") -or ($_.Exception.Response.StatusCode.value__ -eq 400)){
                    $i++
                }
            }
        }
        if($results){
                if($results | get-member | where {$_.name -eq "value"}){
                    $results.value
                }else {
                    $results
                }
            }
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}

$hash_sps = Get-MgServicePrincipal -all | select id, appid, displayname, serviceprincipaltype, PublisherName,accountEnabled | group appid -AsHashTable -AsString

write-host "Total Service Principals $($hash_sps.count)"
$hash_sps.keys | foreach{$hash_sps[$_]} | select serviceprincipaltype | group serviceprincipaltype | select name, count

write-host "Exporting Service Principals that have signin info"
$uri = "https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities"
getFromMSGraph -uri $uri | select appid,  ` 
    @{N="id";E={$hash_sps[$_.appid].id}}, `
    @{N="displayname";E={$hash_sps[$_.appid].displayname}}, `
    @{N="Serviceprincipaltype";E={$hash_sps[$_.appid].Serviceprincipaltype}}, `
    @{N="PublisherName";E={$hash_sps[$_.appid].PublisherName}}, `
    @{N="accountEnabled";E={$hash_sps[$_.appid].accountEnabled}}, `
    @{N="lastSignInActivity";E={$_.lastSignInActivity.lastSignInDateTime}}, `
    @{N="SignInActivityType";E={if($_.delegatedClientSignInActivity.lastSignInDateTime){"delegated"
        }elseif($_.delegatedResourceSignInActivity.lastSignInDateTime){"delegated"
        }elseif($_.applicationAuthenticationClientSignInActivity.lastSignInDateTime){"application"
        }elseif($_.applicationAuthenticationResourceSignInActivity.lastSignInDateTime){"application"
        }else{"unknown"}}} | where {$_.Serviceprincipaltype -ne "ManagedIdentity" -and !($_.id -eq $null)} | `
            export-csv .\AADServicePrincipallastSignInActivity.csv -notypeinformation

write-host "Exporting Service Principals with no signin info"
$hash_splastsignin = import-csv .\AADServicePrincipallastSignInActivity.csv | select appid | group appid -AsHashTable -AsString
$hash_sps.keys | foreach{$hash_sps[$_]} | where {$_.Serviceprincipaltype -ne "ManagedIdentity" -and !($hash_splastsignin.containskey($_.appid)) -and !($_.displayname -eq "workflow")} | select `
    id, appid, displayname, serviceprincipaltype, PublisherName,accountEnabled | export-csv .\AADServicePrincipalNOlastSignInActivityInfo.csv -notypeinformation
