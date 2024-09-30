# Microsoft.graph cmd for guest (b2b) objects

## Connect to Microsoft Graph and switch cmdlets to beta (everything good is in beta)
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All" 
Select-MgProfile -Name beta
```

## Get All Guest User Basics 
```
#count the number of guest
Get-MgBetaUserCount -Filter "userType eq 'Guest'"  -ConsistencyLevel "Eventual"

#get a list of the number of guest.
Get-MgUser -Filter "userType eq 'Guest'" -All -Select displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled,externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail,lastPasswordChangeDateTime | select `
  displayName, signInActivity, userPrincipalName, userType,onPremisesSyncEnabled, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime
```

## Get All Guest that are PendingAcceptance
```
#Count the number of guest that are pending acceptance.
Get-MgBetaUserCount -Filter "userType eq 'Guest' and ExternalUserState eq 'PendingAcceptance'"  -ConsistencyLevel "Eventual"

#Get a list of guest users pending acceptance.
Get-MgUser -Filter "userType eq 'Guest' and ExternalUserState eq 'PendingAcceptance'" -All -Select id, displayName, userPrincipalName, userType, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail | select `
    id, displayName, userPrincipalName, userType, externalUserState, externalUserStateChangeDateTime, creationType, createdDateTime, accountEnabled, mail
```

## How to remove guest users
* remove-mguser in at least version 1.95
  * doesnt actually accept an object, it is looking for Remove-MgUser -InputObject <IUsersIdentity> this tells me no passing object in pipeline
  * powershell also supports attribute to parameter mapping but id doesnt map to userid, so this is another dumb failure
  * pipeline variable for what ever reason doesnt work either no common params
* 
 ```
#does not work
$id = "5abfde79-5c18-42f9-acd8-fcc4c1ef393c" #put the guid of the user needing deleted
Get-MgUser -UserId $id | Remove-MgUser
  
#have to run a foreach :( but the pipeline variable doesnt work
Get-MgUser -UserId $id -pipelinevariable g | foreach{Remove-MgUser -userid $g.id}
  
#so have to do it this way
Get-MgUser -UserId $id | foreach{Remove-MgUser -userid $_.id}

```

## How to remove guest that have not accepted after 30 days
```
Get-MgUser -Filter "userType eq 'Guest' and ExternalUserState eq 'PendingAcceptance' and CreationType eq 'Invitation'" -All -Select id, displayName, userPrincipalName, userType, externalUserState, externalUserStateChangeDateTime | `
    where {(New-TimeSpan -start $_.externalUserStateChangeDateTime -end (get-date)).days -gt 30} | foreach{Remove-MgUser -userid $_.id}
```

## How to restore deleted guest
* do we use restore-mguser or Restore-MgDirectoryObject (neither seem to work)
```

##validate it is deleted
Get-MgDirectoryDeletedItem -DirectoryObjectId $id
  
DeletedDateTime       Id                                   AdditionalProperties
---------------       --                                   --------------------
4/14/2022 10:48:12 PM 5abfde79-5c18-42f9-acd8-fcc4c1ef393c {[@odata.context, https://graph.microsoft.com/beta/$metadata#directoryObjects/$entity], [@odata.type, #microsoft.graph....

#see more info about it
Get-MgDirectoryDeletedItem -DirectoryObjectId $id | select -ExpandProperty AdditionalProperties

#Completely remove the object
Remove-MgDirectoryDeletedItem -DirectoryObjectId $id
  
```
