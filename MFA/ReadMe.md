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
