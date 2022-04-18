param($defaultpath="$env:USERPROFILE\downloads",$pwdnochangedindays = 480)
cd $defaultpath
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All" 
Select-MgProfile -Name beta

Get-MgUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id,displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,passwordPolicies,mail,lastPasswordChangeDateTime | `
    select id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,passwordPolicies, `
        @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}} | `
            where {(New-TimeSpan -Start $_.lastPasswordChangeDateTime -end $(get-date)).TotalDays -gt $pwdnochangedindays} | export-csv .\aad_users_stalepasswords.csv -notypeinformation
            
write-host "Report can be found here cd $defaultpath"
