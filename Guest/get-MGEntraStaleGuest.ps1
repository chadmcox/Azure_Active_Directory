param($defaultpath="$env:USERPROFILE\downloads",$notsignedonindays = 120)
cd $defaultpath
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All" 

Get-MgBetaUser -Filter "userType eq 'Guest' and AccountEnabled eq true" -all  -Property id,displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,externalUserState,externalUserStateChangeDateTime,accountEnabled,passwordPolicies,mail,lastPasswordChangeDateTime | `
    select id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,passwordPolicies, `
      externalUserState,@{Name="externalUserStateChangeDateTime";Expression={(get-date $_.externalUserStateChangeDateTime).tostring('yyyy-MM-dd')}},creationType, `
        @{Name="lastSuccessfulSignInDateTime";Expression={(get-date $_.signInActivity.lastSuccessfulSignInDateTime).tostring('yyyy-MM-dd')}}, `
        @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}} | `
            where {($_.LastSignInDateTime -eq $null)  -or ((New-TimeSpan -Start $_.LastSignInDateTime -end $(get-date)).TotalDays -gt $notsignedonindays)} | `
            where {($_.LastNonInteractiveSignInDateTime -eq $null) -or ((New-TimeSpan -Start $_.LastNonInteractiveSignInDateTime -end $(get-date)).TotalDays -gt $notsignedonindays)} | `
                export-csv .\entra_guest_StaleLastSignIn.csv -notypeinformation
write-host "Report can be found here cd $defaultpath"
