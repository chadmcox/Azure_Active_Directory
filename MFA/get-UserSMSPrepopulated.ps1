param($resultslocation = "$env:USERPROFILE\Downloads")

cd $resultslocation

Connect-MgGraph -Scopes "User.Read.All","UserAuthenticationMethod.Read.All"

$hash_AuthMeth = @{}
$hash_SSPR = @{}
$hash_SSPRCapable = @{}
$hash_SSPRRegistered = @{}
$uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails"
write-host "Creating hash for auth methods"
while ($uri) {
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
               
    $response.value | ForEach-Object {
        $hash_AuthMeth.Add($_.id,($_.methodsRegistered).Count)
        $hash_SSPR.Add($_.id,$_.isSsprEnabled)
        $hash_SSPRCapable.Add($_.id,$_.isSsprCapable)
        $hash_SSPRRegistered.Add($_.id,$_.isSsprRegistered)
    }
    $uri = $response.'@odata.nextLink'
}
write-host "getting all users"
$uri = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Member' and AccountEnabled eq true&`$selectid,displayName,userPrincipalName,mobilePhone,otherMails,businessPhones"

$users = while ($uri) {
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject  
    $response.value 
    $uri = $response.'@odata.nextLink'
}

$users | select DisplayName,UserPrincipalName, MobilePhones,`
    @{N='businessPhones';E={$_.businessPhones -join ';'}},
    @{N='AlternateEmail';E={$_.otherMails -join ';'}},
    @{N='RegisteredMethods';E={$hash_AuthMeth[$_.id]}},
    @{N='isSsprEnabled';E={$hash_SSPR[$_.id]}},
    @{N='isSsprCapable';E={$hash_SSPRCapable[$_.id]}},
    @{N='isSsprRegistered';E={$hash_SSPRRegistered[$_.id]}} | Where-Object {
        ($_.MobilePhone -or $_.AlternateEmail -or $_.businessPhones) -and
        ($_.RegisteredMethods -eq 0)
} | export-csv .\Prepopulate_user_authentication.csv -notypeinformation
