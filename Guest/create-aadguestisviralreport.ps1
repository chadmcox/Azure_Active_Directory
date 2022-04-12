<#
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

get-mguser -Filter "usertype eq 'Guest'" -all | foreach{$guest="";$guest = $_; $results=""
    $userRealmUriFormat = "https://login.microsoftonline.com/common/userrealm?user={urlEncodedMail}&api-version=2.1"
    $encodedMail = [System.Web.HttpUtility]::UrlEncode($guest.Mail)
    $userRealmUri = $userRealmUriFormat -replace "{urlEncodedMail}", $encodedMail
    try{$results = Invoke-WebRequest -Uri $userRealmUri}catch{}
    $results.Content | ConvertFrom-Json
} | select Login, DomainName, FederationBrandName, IsViral | export-csv .\aad_guest_isviral.csv -NoTypeInformation
