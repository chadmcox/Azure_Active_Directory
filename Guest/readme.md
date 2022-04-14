# Microsoft.graph cmd

## Get Guest User Basic 
```
Get-MgUser -Filter "userType eq 'Guest'" -All -Select displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled,externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail,lastPasswordChangeDateTime | select `
  displayName, signInActivity, userPrincipalName, userType,onPremisesSyncEnabled, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime
```
