#Requires -module Microsoft.Graph.Authentication
<#
.GUID 18c37c40-e24d-4524-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk

.Description
this script will remove guest users


#>
param($resultslocation = "$env:USERPROFILE\Downloads",$notacceptedindays = 30,$removalthreshold = 100)

write-host "Looking for Guest that have not signed in for $notsignedonindays days"
Write-host "Will only remove the first $removalthreshold Guest users"

Connect-MgGraph -Scopes "User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All","User.ReadWrite.All","Directory.ReadWrite.All"
cd $resultslocation

function getAADGuest{
    [cmdletbinding()] 
    param()
    write-host "Exporting all Guest to: $resultslocation, this may take a while"
    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest' and externalUserState eq 'PendingAcceptance'&`$select=id,displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime"
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
function removeAADGuest{
    [cmdletbinding()] 
    param($guestid)
    try{
        $uri = "https://graph.microsoft.com/beta/users/$guestid"
        Invoke-MgGraphRequest -Uri $Uri -Method Delete -ContentType "application/json"
    }catch{
        Write-Output "$($_.Exception.Response.StatusCode)"
    }
}

getAADGuest -pv guest | where {!($_.onPremisesSyncEnabled -eq $true)} | `
    where {(NEW-TIMESPAN –Start $_.externalUserStateChangeDateTime –End $today).days -gt $notacceptedindays} | `
    select * -first $removalthreshold | foreach{
    write-host "Removing $($guest.userPrincipalName) - $($guest.onPremisesSyncEnabled) - $($_.signInActivity.lastSignInDateTime) - $($_.signInActivity.lastNonInteractiveSignInDateTime)"
    "Removing $($guest.userPrincipalName) - $($guest.onPremisesSyncEnabled) - $($_.signInActivity.lastSignInDateTime) - $($_.signInActivity.lastNonInteractiveSignInDateTime)" | add-content ".\removeaadguest.log"
    removeAADGuest -guestid $guest.id
}
