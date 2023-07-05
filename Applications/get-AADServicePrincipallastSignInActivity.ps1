param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory
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

$hash_sps = Get-MgServicePrincipal -all | select id, appid, displayname, serviceprincipaltype | group appid -AsHashTable -AsString

write-host "Total Service Principals $($hash_sps.count)"
$hash_sps.keys | foreach{$hash_sps[$_]} | select serviceprincipaltype | group serviceprincipaltype | select name, count

$uri = "https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities"
getFromMSGraph -uri $uri | select appid,  ` 
    @{N="id";E={$hash_sps[$_.appid].id}}, `
    @{N="displayname";E={$hash_sps[$_.appid].displayname}}, `
    @{N="Serviceprincipaltype";E={$hash_sps[$_.appid].Serviceprincipaltype}}, `
    @{N="lastSignInActivity";E={$_.lastSignInActivity.lastSignInDateTime}}, `
    @{N="SignInActivityType";E={if($_.delegatedClientSignInActivity.lastSignInDateTime){"delegated"
        }elseif($_.delegatedResourceSignInActivity.lastSignInDateTime){"delegated"
        }elseif($_.applicationAuthenticationClientSignInActivity.lastSignInDateTime){"application"
        }elseif($_.applicationAuthenticationResourceSignInActivity.lastSignInDateTime){"application"
        }else{"unknown"}}} | where {$_.Serviceprincipaltype -ne "ManagedIdentity" -and !($_.id -eq $null)} | `
            export-csv .\AADServicePrincipallastSignInActivity.csv -notypeinformation
