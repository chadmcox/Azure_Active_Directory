Connect-MgGraph -Scopes "Policy.Read.All","Reports.Read.All","AuditLog.Read.All","Directory.Read.All","Directory.Read.All","User.Read.All","AuditLog.Read.All","IdentityRiskyUser.Read.All","IdentityRiskEvent.Read.All","Reports.Read.All","UserAuthenticationMethod.Read.All","AuditLog.Read.All"

function get-AADuserRegistrationDetails{
    [cmdletbinding()] 
    param()
    write-host "Exporting all riskyusers to: $resultslocation, this may take a while"
$uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$filter=methodsRegistered/any(s:s eq 'windowsHelloForBusiness')"
#$uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$filter=isMfaCapable eq True)"
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

get-AADuserRegistrationDetails | where {$_} | Export-Csv .\wh4bregistered.csv -NoTypeInformation -ErrorAction Continue
