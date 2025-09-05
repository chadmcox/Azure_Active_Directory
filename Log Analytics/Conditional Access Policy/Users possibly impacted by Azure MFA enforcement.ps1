//link to blog post https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/update-on-mfa-requirements-for-azure-sign-in/ba-p/4177584
//this will get all users successfully signing into the azure endpoints that are going to get mfa enforcement
let includeapps = pack_array("Windows Azure Service Management API","Azure Portal");
let appguids = pack_array("c44b4083-3bb0-49c1-b47d-974e53cbdf3c","04b07795-8ddb-461a-bbee-02f9e1bf7b46","1950a258-227b-4e31-a9cf-717495945fc2","0c1307d4-29d6-4389-a11c-5cbe7f65d7fa");
let s = SigninLogs
| where CreatedDateTime >= ago(30d)
| where AADTenantId == ResourceTenantId
| where ResultType == 0 and AuthenticationRequirement == "singleFactorAuthentication" 
| where  ResourceDisplayName in (includeapps) or AppDisplayName in (includeapps) or AppDisplayName in (appguids) or ResourceDisplayName in (appguids)
| where Status !contains "MFA requirement satisfied by claim in the token"
| mv-apply ca=todynamic(ConditionalAccessPolicies) on (
    summarize condition1 = countif(ca.result in ("success") and tostring(ca.enforcedGrantControls) contains 'Mfa')
)
| where condition1 == 0
| distinct AppDisplayName, UPN = tolower(UserPrincipalName), ConditionalAccessStatus, AuthenticationRequirement;
let n = AADNonInteractiveUserSignInLogs
| where CreatedDateTime >= ago(30d)
| where AADTenantId == ResourceTenantId
| where ResultType == 0 and AuthenticationRequirement == "singleFactorAuthentication" 
| where  ResourceDisplayName in (includeapps) or AppDisplayName in (includeapps) or AppDisplayName in (appguids) or ResourceDisplayName in (appguids)
| where Status !contains "MFA requirement satisfied by claim in the token"
| mv-apply ca=todynamic(ConditionalAccessPolicies) on (
    summarize condition1 = countif(ca.result in ("success") and tostring(ca.enforcedGrantControls) contains 'Mfa')
)
| where condition1 == 0
| distinct AppDisplayName, UPN = tolower(UserPrincipalName), ConditionalAccessStatus, AuthenticationRequirement;
union s, n
| summarize apps=make_set(AppDisplayName) by UPN, ConditionalAccessStatus, AuthenticationRequirement
