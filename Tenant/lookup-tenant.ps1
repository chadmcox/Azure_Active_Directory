param($email)
cls
if(!($email)){
    $email = read-host "Enter email address or domain name"
}
Add-Type -AssemblyName System.Web
$userRealmUriFormat = "https://login.microsoftonline.com/common/userrealm?user={urlEncodedMail}&api-version=2.1"
$encodedMail = [System.Web.HttpUtility]::UrlEncode($email)
$userRealmUri = $userRealmUriFormat -replace "{urlEncodedMail}", $encodedMail
$results = Invoke-WebRequest -Uri $userRealmUri
$results.content | convertfrom-json
