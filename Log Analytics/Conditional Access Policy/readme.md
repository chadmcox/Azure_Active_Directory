### Prereqs for running these queries
[Integrate Azure AD logs with Azure Monitor logs](https://learn.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-integrate-activity-logs-with-log-analytics)

### Notes:
* This is a list of queries I have thrown together to help work on conditional access policies.  The idea is to find the users that could be impacted by a particular policy example is Require guest to MFA.kql will show a list of guest who do not currently mfa when they log into anything in Azure AD.
* A majority of the policies can be found as guidance from [Zero Trust identity and device access configurations](https://learn.microsoft.com/en-us/microsoft-365/security/office-365-security/microsoft-365-policies-configurations?view=o365-worldwide)
* I have also put together a PowerShell script to help figure out which policies are missing. [Find script here](https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/retrieve-ztibaselineconditionalaccesspolicies.ps1)
* My Conditional Access Policy Wiki has a list of conditional access policies I recommend. [Link to wiki]()
* 

