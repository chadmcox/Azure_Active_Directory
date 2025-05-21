function getAADUsers{
    [cmdletbinding()] 
    param()
    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'member'&`$select=id,displayName,userprincipalname,othermails"
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


Connect-MgGraph -Scopes "UserAuthenticationMethod.Read", "Directory.ReadWrite.All", "Directory.AccessAsUser.All"

getAADUsers -pv user | where {$_.othermails -match "gmail|hotmail|msn|ymail|aol|msn|outlook|live|googlemail|yahoo|cox.com|verizon.net|att.net|wanadoo|orange|comcast.net|facebook"} | select `
    id,userprincipalname,@{N="othermails";E={[string]$($_.othermails)}} | export-csv "$env:USERPROFILE\downloads\AAD_User_AlternateEmail.csv" -notypeinformation
    
write-host "find results here $env:USERPROFILE\downloads"
