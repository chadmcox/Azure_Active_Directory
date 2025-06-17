#install microsoft.graph if currently not installed
install-module microsoft.graph
#connect to microsoft graph powershell
Connect-MgGraph -Scopes "Policy.Read.All","Directory.Read.All","User.Read.All","Reports.Read.All", "UserAuthenticationMethod.Read.All"

cd "$env:USERPROFILE\downloads"

function mgquery{
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
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}

$uri = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,identities&`$filter=identities/any(x:x/issuer eq 'phone')"
mgquery -uri $uri -pv user | select id, displayname -ExpandProperty identities | where {$_.issuer -eq "phone"} | export-csv .\entra_users_phone_issuers.csv -NoTypeInformation
