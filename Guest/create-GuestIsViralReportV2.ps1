<#
.GUID 2635c447-4c54-4b44-86e4-67c950ca1f9a
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk
.Description
This is a basic script that goes out to graph and pulls back guest objects and their last interactive authentication date.
and their authentication time
#>

param($defaultpath="$env:USERPROFILE\downloads")

Connect-AzAccount
$script:accessToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
Add-Type -AssemblyName System.Web

$script:authHeader = @{
      "Authorization" = "Bearer " + $AccessToken
    }

function query-msgraphapi{
    [cmdletbinding()]
    param($uri)
    $authcount = 0
    do{$results = $null
        if($authcount -gt 300){
            #might have a timeout condition occuring so making it get a new access token every 3000 users
            $script:accessToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
            Add-Type -AssemblyName System.Web

            $script:authHeader = @{
                  "Authorization" = "Bearer " + $AccessToken
                }
            
            $authcount = 0
        }else{
            $authcount++
        }
        for($i=0; $i -le 3; $i++){
            try{$results = $null
                $results = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get -ContentType "application/json"
                break
            }catch{#if this fails it is going to try to authenticate again and rerun query
                $results = $null
                write-host "$($_.Exception.response.statuscode)"
                if(($_.Exception.response.statuscode -eq "TooManyRequests") -or ($_.Exception.Response.StatusCode.value__ -eq 429)){
                    #if this hits up against to many request response throwing in the timer to wait the number of seconds recommended in the response.
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }elseif($_.Exception.response.statuscode -eq "Unauthorized"){
                    $script:accessToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
                    Add-Type -AssemblyName System.Web

                    $script:authHeader = @{
                          "Authorization" = "Bearer " + $AccessToken
                        }
            
                    $authcount = 0
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}
function isguestviral{
    [cmdletbinding()]
    param($mail)
    if(!($global:Hash_DomainisViral.containskey(($mail -split("@"))[1]))){
        $userRealmUriFormat = "https://login.microsoftonline.com/common/userrealm?user={urlEncodedMail}&api-version=2.1"
        $encodedMail = [System.Web.HttpUtility]::UrlEncode($mail)
        $userRealmUri = $userRealmUriFormat -replace "{urlEncodedMail}", $encodedMail
        try{$results = Invoke-WebRequest -Uri $userRealmUri}catch{}
        if(($results.Content | ConvertFrom-Json).IsViral -eq $true){
            ($results.Content | ConvertFrom-Json).IsViral
            $global:Hash_DomainisViral.add(($mail -split("@"))[1],$true)
        }else{
            $false
            $global:Hash_DomainisViral.add(($mail -split("@"))[1],$false)
        }
    }else{$global:Hash_DomainisViral["$(($mail -split("@"))[1])"]}
}

$global:Hash_DomainisViral = @{}

$uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=id,displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,identities&`$expand=memberOf"
query-msgraphapi -uri $uri | select  displayName,userPrincipalName,userType,Mail,externalUserState, creationType,accountEnabled,onPremisesSyncEnabled,`
    @{Name="externalUserStateChangeDateTime";Expression={(get-date $_.externalUserStateChangeDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="createdDateTime";Expression={(get-date $_.createdDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="lastSignInDateTime";Expression={(get-date $_.signInActivity.lastSignInDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="lastNonInteractiveSignInDateTime";Expression={(get-date $_.signInActivity.lastNonInteractiveSignInDateTime).tostring('yyyy-MM-dd')}}, `
    @{Name="SignInType";Expression={($_.identities | where {$_.SignInType -eq "federated"}).Issuer}}, `
    @{Name="Domain";Expression={($_.mail -split("@"))[1]}}, @{Name="UnifiedGroupMember";Expression={$_.memberOf.groupTypes -contains "Unified"}}, `
    @{Name="IsViral";Expression={$SignInType =$null;$SignInType = ($_.identities | where {$_.SignInType -eq "federated"}).Issuer; `
        if(!($SignInType)){isguestviral -mail $_.mail}elseif($SignInType -eq 'ExternalAzureAD'){isguestviral -mail $_.mail}}}  | `
            export-csv "$defaultpath\aad_guests.csv" -NoTypeInformation
