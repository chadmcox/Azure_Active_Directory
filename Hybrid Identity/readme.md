
1) Make sure this url is a trusted site:
https://secure.aadcdn.microsoftonline-p.com

2) TLS must be enabled:
- This script will check the settings: https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Azure%20AD%20Connect/CheckTLSforAADC.ps1
This is what I got from this on a default machine
```
Path                                                                                       Name                     Value    
----                                                                                       ----                     -----    
HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319                              SystemDefaultTlsVersions Not Found
HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319                              SchUseStrongCrypto       1        
HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319                                          SystemDefaultTlsVersions Not Found
HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319                                          SchUseStrongCrypto       1        
HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server Enabled                  Not Found
HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server DisabledByDefault        Not Found
HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client Enabled                  Not Found
HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client DisabledByDefault        Not Found
```

- This script will enable the settings: https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Azure%20AD%20Connect/EnableTLS12forAADC.ps1

3) .Net Framework should be at least 4.6.2




Links to documents
https://docs.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-install-prerequisites

