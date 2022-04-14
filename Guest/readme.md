# Microsoft.graph cmd

```
Get-MgUser -Filter "userType eq 'Guest'" -Select displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled,externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail,lastPasswordChangeDateTime | select `
  displayName, signInActivity, userPrincipalName, userType,onPremisesSyncEnabled, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime
```
