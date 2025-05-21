param($defaultpath="$env:USERPROFILE\downloads",$pwdnochangedindays = 480)
cd $defaultpath

Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"

Get-MgBetaUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id,displayName,signInActivity,userPrincipalName, `
  userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,passwordPolicies,mail,lastPasswordChangeDateTime | `
    select id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,passwordPolicies, `
      @{N='lastSuccessfulSignInDateTime';E={$_.signInActivity.lastSuccessfulSignInDateTime}}, @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, `
      @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}} | export-csv .\aad_user_report.csv -notypeinformation
write-host "Report can be found here cd $defaultpath"
