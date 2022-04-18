# AAD User Scripts

## get a list of users with basic information
```
#make sure the microsoft graph modules are available
get-module microsoft.graph* -list available
#if not install them
install-module microsoft.graph

#connect to mggraph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Select-MgProfile -Name beta
Get-MgUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id, displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled, createdDateTime, accountEnabled, passwordPolicies, mail, lastPasswordChangeDateTime | `
    select id, displayName, userPrincipalName, userType, onPremisesSyncEnabled, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime, passwordPolicies, `
        @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, `
        @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}}
      
```
## Get a list of all Users MFA Status / Registration
### Using Powershell 
```
#connect to mggraph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All","UserAuthenticationMethod.Read.All"
Select-MgProfile -Name beta

#this cmdlet pulls in the list, but the methods registered is a multivalue property so the data doesnt look good
Get-MgReportAuthenticationMethodUserRegistrationDetail -all | select *

#this will write each method to a new line to make it easier to pivot off of.

Get-MgReportAuthenticationMethodUserRegistrationDetail -all | select * | foreach{$users="";$user=$_
    $_.MethodsRegistered | select Id,UserDisplayName,UserPrincipalName,IsMfaCapable,IsMfaRegistered, `
        IsPasswordlessCapable,IsSsprCapable,IsSsprEnabled,IsSsprRegistered,@{N='MethodsRegistered';E={$_}}
}
```

## How to disable a user
* This cmdlet is not very clear on how to do it. 
### Using PowerShell
```
PS C:\> Update-MgUser -UserId 2d192670-c993-4301-bd4a-ea9727ab6546 -AccountEnabled:$false
PS C:\> get-MgUser -UserId 2d192670-c993-4301-bd4a-ea9727ab6546 | select AccountEnabled

AccountEnabled
--------------
         False
  
```
## create-AADMGUserReport.ps1
Get a list of all member users, includes last time password was changed and last time the user logged in.

## 