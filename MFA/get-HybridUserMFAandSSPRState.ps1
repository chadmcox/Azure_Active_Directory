#Requires -RunAsAdministrator
param($path="$env:USERPROFILE\downloads")
cd $path

if(!(get-module Microsoft.Graph.Beta.Reports -listavailable)){
    find-module Microsoft.Graph.Beta.Reports | install-module -force
}

connect-mggraph -scope UserAuthenticationMethod.Read.All, AuditLog.Read.All, User.ReadBasic.All, User.Read.All, Directory.Read.All

write-host "getting all enabled hybrid users"
$enabledusers = get-mgbetauser -filter "UserType eq 'member' and accountEnabled eq true and onPremisesSyncEnabled eq true" -all | select id, accountEnabled, onPremisesSyncEnabled
write-host "creating hash table this will take a moment"
$hash_enabledusers = @{}
$enabledusers | foreach{$hash_enabledusers.Add($_.id,$true)}
write-host "getting all auth method registration details"
$UserRegistrationDetail = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -Filter "UserType eq 'member'" -all | where {$hash_enabledusers.containskey($_.id)} | select UserDisplayName, UserPrincipalName, IsMfaCapable, IsMfaRegistered, IsSsprCapable, IsSsprRegistered, IsSsprEnabled
write-host "Total enabled hybrid users: $($enabledusers.count)"
write-host "IsMfaCapable: $(($UserRegistrationDetail | where {$_.IsMfaCapable -eq $true}).count)"
write-host "IsMfaRegistered: $(($UserRegistrationDetail | where {$_.IsMfaRegistered -eq $true}).count)"
write-host "IsSsprCapable: $(($UserRegistrationDetail | where {$_.IsSsprCapable -eq $true}).count)"
write-host "IsSsprRegistered: $(($UserRegistrationDetail | where {$_.IsSsprRegistered -eq $true}).count)"
write-host "IsSsprEnabled: $(($UserRegistrationDetail | where {$_.IsSsprEnabled -eq $true}).count)"
write-host "User Registration Details can be found here: $path\UserRegistrationDetails.csv"
$UserRegistrationDetail | export-csv .\UserRegistrationDetails.csv -notypeinformation
