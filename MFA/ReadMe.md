# Azure AD MFA


## Get userRegistrationCounts
```
#install microsoft.graph if currently not installed
install-module microsoft.graph
#connect to microsoft graph powershell
Connect-MgGraph -Scopes "Policy.Read.All" ,"Reports.Read.All", "AuditLog.Read.All", "Directory.Read.All", "Directory.Read.All", "User.Read.All", "AuditLog.Read.All", "IdentityRiskyUser.Read.All", "IdentityRiskEvent.Read.All", "Reports.Read.All", "UserAuthenticationMethod.Read.All", "AuditLog.Read.All"

$uri = "https://graph.microsoft.com/beta/reports/getCredentialUserRegistrationCount"
Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject | select -ExpandProperty value | select -ExpandProperty userRegistrationCounts

#results look like

registrationStatus registrationCount
------------------ -----------------
registered                     76000
enabled                         2555
capable                          100
mfaRegistered                  67888

```
## get usersRegisteredByMethod

```
$uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/usersRegisteredByMethod"
Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject | select -ExpandProperty userRegistrationMethodCounts

#results

authenticationMethod               userCount
--------------------               ---------
password                                   0
email                                      7
mobilePhone                            21555
alternateMobilePhone                    1055
officePhone                             1555
microsoftAuthenticatorPush             37555
softwareOneTimePasscode                38555
hardwareOneTimePasscode                    5
microsoftAuthenticatorPasswordless       255
windowsHelloForBusiness                55555
fido2SecurityKey                          55
temporaryAccessPass                        1
securityQuestion                           0
```

## get usersRegisteredByFeature

```
$uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/usersRegisteredByFeature"
Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject  |  select -ExpandProperty userRegistrationFeatureCounts

#results

feature             userCount
-------             ---------
ssprRegistered          75555
ssprEnabled              1555
ssprCapable               155
passwordlessCapable        55
mfaCapable              55555
```

## Retrieve a user Windows Hello for Business Creds
```
$user = "Aaliyah.Poole@lab2.chadcolabs.us"
$uri = "https://graph.microsoft.com/beta/users/$user/authentication/windowsHelloForBusinessMethods"
$results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
$results.value

id                                           displayName     createdDateTime      keyStrength
--                                           -----------     ---------------      -----------
3saW-g-7i0xkB-me9XqIHSfAHwH5MhLWZobhcoS0s5E1 DESKTOP-BBNFIJG 5/9/2022 7:03:18 PM  normal     
zt9F5ojyFo5KV8Fio2IHJGOcaMaM3vSCQ1lzu0Lw_W01                 9/14/2020 8:13:34 PM normal  

```

## Try to query the cred directly 
```
$wh4bmId = "zt9F5ojyFo5KV8Fio2IHJGOcaMaM3vSCQ1lzu0Lw_W01"
$uri = "https://graph.microsoft.com/beta/users/$user/authentication/windowsHelloForBusinessMethods/$wh4bmId"
Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject


@odata.context  : https://graph.microsoft.com/beta/$metadata#users('Aaliyah.Poole%40lab2.chadcolabs.us')/authentication/windowsHelloForBusinessMethods/$entity
id              : zt9F5ojyFo5KV8Fio2IHJGOcaMaM3vSCQ1lzu0Lw_W01
displayName     : DESKTOP-CK55VTK
createdDateTime : 9/14/2020 8:13:34 PM
keyStrength     : normal
```

## Remove one of the user's WH4B creds
```
Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All"
$uri = "https://graph.microsoft.com/beta/users/$user/authentication/windowsHelloForBusinessMethods/$wh4bmId"
Invoke-MgGraphRequest -Uri $uri -Method DELETE -OutputType PSObject

```
rerun the the cmdlets to retrive the users stored wh4b creds and notice the cred is now gone.

## Manually Launch Windows Hello for Business Provisioning
```
ms-cxh://nthaad
```
