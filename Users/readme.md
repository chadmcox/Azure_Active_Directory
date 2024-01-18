# AAD User Scripts / CMDlets

## get a list of users with basic sign-in and pwd information
```
#make sure the microsoft graph modules are available
get-module microsoft.graph* -listavailable
#if not install them
install-module microsoft.graph

#connect to mggraph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Get-MgBetaUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id, displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled, createdDateTime, accountEnabled, passwordPolicies, mail, lastPasswordChangeDateTime,onPremisesLastSyncDateTime | `
    select id, displayName, userPrincipalName, userType, onPremisesSyncEnabled, accountEnabled, mail, `
        @{Name="createdDateTime";Expression={(get-date $_.createdDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="onPremisesLastSyncDateTime";Expression={(get-date $_.onPremisesLastSyncDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="lastPasswordChangeDateTime";Expression={if($_.createdDateTime -ne $_.lastPasswordChangeDateTime){(get-date $_.lastPasswordChangeDateTime).tostring('yyyy-MM-dd')}}}, `
        @{Name="lastSuccessfulSignInDateTime";Expression={(get-date $_.signInActivity.lastSuccessfulSignInDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="lastSignInDateTime";Expression={(get-date $_.signInActivity.lastSignInDateTime).tostring('yyyy-MM-dd')}}, `
        @{Name="lastNonInteractiveSignInDateTime";Expression={(get-date $_.signInActivity.lastNonInteractiveSignInDateTime).tostring('yyyy-MM-dd')}}
      
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

## Get a list of Users that are more than likely enabled shared mailboxes. 
### Using Powershell 
```
#connect to mggraph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All","UserAuthenticationMethod.Read.All"

Get-MgBetaUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id, displayName, signInActivity, userPrincipalName, userType, onPremisesSyncEnabled, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime, AssignedLicenses,proxyAddresses | `
    where {$_.onPremisesSyncEnabled -ne $true -and $_.mail -like "*@*" -and !($_.AssignedLicenses -ne $null)} | `
        select id, displayName, userPrincipalName, userType, onPremisesSyncEnabled, createdDateTime, accountEnabled, mail, lastPasswordChangeDateTime
```
