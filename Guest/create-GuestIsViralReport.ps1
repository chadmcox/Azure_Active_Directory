#Requires -module Microsoft.Graph.Authentication
<#
.GUID 18c37c40-e24d-4524-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk
.Description
the recommendation is to enable guest otp and to use this results to initiate a reinvite of the guest

#https://blog.astashin.com/blog/Bring-em-all-in-p4/
#working out what to do with this
https://docs.microsoft.com/en-us/azure/active-directory/external-identities/faq#do-you-support-password-reset-for-azure-ad-b2b-collaboration-users- 
If the identity tenant is a just-in-time (JIT) or "viral" tenant (meaning it's a separate, unmanaged Azure tenant), 
only the guest user can reset their password. Sometimes an organization will take over management of viral tenants that are 
created when employees use their work email addresses to sign up for services. After the organization takes over a viral tenant, 
only an administrator in that organization can reset the user's password or enable SSPR. If necessary, as the inviting organization, 
you can remove the guest user account from your directory and resend an invitation.
https://docs.microsoft.com/en-us/azure/active-directory/external-identities/reset-redemption-status
#>
param($resultslocation = "$env:USERPROFILE\Downloads")
Add-Type -AssemblyName System.Web
Connect-MgGraph -Scopes "User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All"

function getAADGuest{
    [cmdletbinding()] 
    param()
    write-host "Exporting all Guest to: $resultslocation, this may take a while"
    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,externalUserState,externalUserStateChangeDateTime,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,identities"
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


getAADGuest | where {!($_.onPremisesSyncEnabled -eq $true) -and ($_.identities | where {$_.SignInType -eq "federated"}).Issuer -eq "ExternalAzureAD"} | `
    foreach{$guest="";$guest = $_; $results=""
        if($guest.Mail){
        $userRealmUriFormat = "https://login.microsoftonline.com/common/userrealm?user={urlEncodedMail}&api-version=2.1"
        $encodedMail = [System.Web.HttpUtility]::UrlEncode($guest.Mail)
        $userRealmUri = $userRealmUriFormat -replace "{urlEncodedMail}", $encodedMail
        try{$results = Invoke-WebRequest -Uri $userRealmUri}catch{$guest.mail | add-content .\aad_guest_notfound.txt}
        }
        $guest | select userprincipalname, @{Name="Login";Expression={if($results){($results.Content | ConvertFrom-Json).Login}else{"NA"}}}, `
            @{Name="DomainName";Expression={if($results){($results.Content | ConvertFrom-Json).DomainName}else{"NA"}}}, `
            @{Name="FederationBrandName";Expression={if($results){($results.Content | ConvertFrom-Json).FederationBrandName}}}, `
            @{Name="IsViral";Expression={if($results){($results.Content | ConvertFrom-Json).IsViral}}}, `
            @{Name="SignInType";Expression={($_.identities | where {$_.SignInType -eq "federated"}).Issuer}}, `
        @{Name="createdDateTime";Expression={(get-date $_.createdDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="lastPasswordChangeDateTime";Expression={if($_.createdDateTime -ne $_.lastPasswordChangeDateTime){(get-date $_.lastPasswordChangeDateTime).tostring('yyyy-MM-dd')}}}, `
        @{Name="lastSignInDateTime";Expression={(get-date $_.signInActivity.lastSignInDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="lastNonInteractiveSignInDateTime";Expression={(get-date $_.signInActivity.lastNonInteractiveSignInDateTime).tostring('yyyy-MM-dd')}}
} | where {$_.IsViral -eq $true}  | export-csv .\aad_guest_isviral.csv -NoTypeInformation
