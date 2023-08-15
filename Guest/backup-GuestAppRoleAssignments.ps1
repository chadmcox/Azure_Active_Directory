param($resultslocation = "$env:USERPROFILE\Downloads")
cd $resultslocation
Connect-MgGraph -Scopes "User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All"
function getAADGuest{
    [cmdletbinding()] 
    param()
    write-host "Exporting all Guest to: $resultslocation, this may take a while"
    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime&`$expand=appRoleAssignments"
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

$all_guest = getAADGuest

$all_guest | where {$_.appRoleAssignments -like "*"} | select id,displayName,userPrincipalName,userType,onPremisesSyncEnabled, `
    externalUserState,creationType,accountEnabled,mail, appRoleAssignments | convertto-json -depth 99 | out-file .\backup_guest_appRoleAssignments.json

write-host "Results can be found here: $resultslocation"
