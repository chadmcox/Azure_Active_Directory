# Microsoft.graph cmd for guest (b2b) objects

## Connect to Microsoft Graph and switch cmdlets to beta (everything good is in beta)
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All" 
Select-MgProfile -Name beta
```

## Get All Guest User Basics 
```
Get-MgUser -Filter "userType eq 'Guest'" -All -Select displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled,externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail,lastPasswordChangeDateTime | select `
  displayName, signInActivity, userPrincipalName, userType,onPremisesSyncEnabled, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime
```

## Get All Guest that are PendingAcceptance
```
Get-MgUser -Filter "userType eq 'Guest' and ExternalUserState eq 'PendingAcceptance'" -All -Select id, displayName, userPrincipalName, userType, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail | select `
    id, displayName, userPrincipalName, userType, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail
```
