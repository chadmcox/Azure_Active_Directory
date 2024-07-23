//link to blog post https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/update-on-mfa-requirements-for-azure-sign-in/ba-p/4177584
//this will get all users successfully signing into the azure endpoints that are going to get mfa enforcement
SigninLogs 
| where AADTenantId == ResourceTenantId
| where ResultType == 0 and AuthenticationRequirement == "singleFactorAuthentication" 
| extend TrustedLocation = tostring(iff(NetworkLocationDetails contains 'trustedNamedLocation', 'trustedNamedLocation',''))
| where AppId in ("c44b4083-3bb0-49c1-b47d-974e53cbdf3c","04b07795-8ddb-461a-bbee-02f9e1bf7b46","1950a258-227b-4e31-a9cf-717495945fc2") 
| where Status !contains "MFA requirement satisfied by claim in the token"
| mv-apply ca=todynamic(ConditionalAccessPolicies) on (
    summarize condition1 = countif(ca.result in ("success") and tostring(ca.enforcedGrantControls) contains 'Mfa')
)
| where condition1 == 0
| distinct AppDisplayName, UPN = tolower(UserPrincipalName), ConditionalAccessStatus, AuthenticationRequirement, TrustedLocation
