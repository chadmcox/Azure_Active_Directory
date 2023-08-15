param($resultslocation = "$env:USERPROFILE\Downloads")
cd $resultslocation
Connect-MgGraph -Scopes "User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All"
function getAADGuest{
    [cmdletbinding()] 
    param()
    write-host "Exporting all Guest to: $resultslocation, this may take a while"
    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime&`$expand=sponsors(`$select=id,displayName)"
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

$all_guest | select displayName,userPrincipalName,userType,externalUserState, `
    @{Name="externalUserStateChangeDateTime";Expression={(get-date $_.externalUserStateChangeDateTime).tostring('yyyy-MM-dd')}}, `
    creationType,accountEnabled,onPremisesSyncEnabled,Mail, `
    @{Name="createdDateTime";Expression={(get-date $_.createdDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="lastPasswordChangeDateTime";Expression={if($_.createdDateTime -ne $_.lastPasswordChangeDateTime){(get-date $_.lastPasswordChangeDateTime).tostring('yyyy-MM-dd')}}}, `
    @{Name="lastSignInDateTime";Expression={(get-date $_.signInActivity.lastSignInDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="lastNonInteractiveSignInDateTime";Expression={(get-date $_.signInActivity.lastNonInteractiveSignInDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="Domain";Expression={($_.mail -split("@"))[1]}}, @{Name="Sponsors";Expression={($_.sponsors.displayName -join(";"))}}  | export-csv .\azuread_guestusers.csv -notypeinformation

write-host "Results can be found here: $resultslocation"
