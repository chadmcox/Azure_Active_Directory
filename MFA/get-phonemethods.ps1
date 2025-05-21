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

$uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails"
$users = mgquery -uri $uri -pv user | select id, userPrincipalName, userDisplayName
$count = $users.count; $i=0
$users | select id, userPrincipalName, userDisplayName -pv user | foreach {$i++
    Write-host "$i of $count"
    $uri = "https://graph.microsoft.com/beta/users/$($user.userPrincipalName)/authentication/phoneMethods"
    Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject | select -ExpandProperty value | select `
        @{N="id";E={$user.id}}, `
        @{N="userPrincipalName";E={$user.userPrincipalName}}, `
        @{N="userDisplayName";E={$user.userDisplayName}}, `
       phoneNumber, phoneType, smsSignInState
}  | export-csv .\phone_export.csv -NoTypeInformation
