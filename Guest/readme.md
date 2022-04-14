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

## How to remove guest users
* remove-mguser in at least version 1.95
  * doesnt actually accept an object, it is looking for Remove-MgUser -InputObject <IUsersIdentity>  but the output of the get-mguser is a Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser
  * powershell also supports attribute to parameter mapping but id doesnt map to userid, so this is another dumb failure
  * pipeline variable for what ever reason doesnt work either no common params

 ```
#does not work
Get-MgUser -UserId "5abfde79-5c18-42f9-acd8-fcc4c1ef393c" | Remove-MgUser
#have to run a foreach :( but the pipeline variable doesnt work
Get-MgUser -UserId "5abfde79-5c18-42f9-acd8-fcc4c1ef393c" -pipelinevariable g | foreach{Remove-MgUser -userid $g.id}
#so have to do it this way
Get-MgUser -UserId "5abfde79-5c18-42f9-acd8-fcc4c1ef393c" | foreach{Remove-MgUser -userid $_.id}

```
