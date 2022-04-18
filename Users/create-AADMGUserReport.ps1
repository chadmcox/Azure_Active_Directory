Get-MgUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id,displayName,signInActivity,userPrincipalName, `
  userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,passwordPolicies,mail,lastPasswordChangeDateTime | `
    select id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,passwordPolicies, `
        @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}} | `
          export-csv .\aad_user_report.csv -notypeinformation
