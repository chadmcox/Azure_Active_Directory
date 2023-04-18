.GUID 18c37c40-e24d-4524-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk
.Description
This is a basic script that goes out to graph and pulls back guest objects and their last interactive authentication date.

#>

param($defaultpath="$env:USERPROFILE\downloads")

Connect-AzAccount
$accessToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

$authHeader = @{
      "Authorization" = "Bearer " + $AccessToken
    }

function query-msgraphapi{
    [cmdletbinding()]
    param($uri)
    do{$results = $null
        for($i=0; $i -le 3; $i++){
            try{
                $results = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get -ContentType "application/json"
                break
            }catch{#if this fails it is going to try to authenticate again and rerun query
                if(($_.Exception.response.statuscode -eq "TooManyRequests") -or ($_.Exception.Response.StatusCode.value__ -eq 429)){
                    #if this hits up against to many request response throwing in the timer to wait the number of seconds recommended in the response.
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}

$uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime&`$expand=memberOf"
query-msgraphapi -uri $uri | select  displayName,userPrincipalName,userType,externalUserState,@{Name="externalUserStateChangeDateTime";Expression={(get-date $_.externalUserStateChangeDateTime).tostring('yyyy-MM-dd')}},creationType,`
    @{Name="createdDateTime";Expression={(get-date $_.createdDateTime).tostring('yyyy-MM-dd')}},accountEnabled,onPremisesSyncEnabled, @{Name="lastSignInDateTime";Expression={(get-date $_.signInActivity.lastSignInDateTime).tostring('yyyy-MM-dd')}},Mail, `
    @{Name="lastNonInteractiveSignInDateTime";Expression={(get-date $_.signInActivity.lastNonInteractiveSignInDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="Domain";Expression={($_.mail -split("@"))[1]}}, @{Name="UnifiedGroupMember";Expression={$_.memberOf.groupTypes -contains "Unified"}} | export-csv "$defaultpath\aad_guests.csv" -NoTypeInformation
write-host "Results can be found here: $defaultpath\aad_guests.csv"
