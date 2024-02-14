# How to successfully implment Entra ID Protection.

 * Requirement:  Entra ID (Azure AD)  logs need to be integrated with Azure monitor.  [Integrate Azure AD logs with Azure Monitor logs](https://learn.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-integrate-activity-logs-with-azure-monitor-logs)

## Trusted Locations

## Existing risk cleanup
### Export existing risk to a file
```
install-module Microsoft.Graph.Beta.Identity.SignIns

Connect-MgGraph -Scopes IdentityRiskEvent.Read.All

Get-MgBetaRiskyUser -filter "RiskState eq 'atRisk'"  -All | `
    select Id, UserDisplayName, UserPrincipalName, RiskLevel, RiskState, RiskDetail, RiskLastUpdatedDateTime, IsProcessing, IsDeleted | `
        export-csv .\current_users_at_risk.csv -notypeinformation
```
### Dismiss user risk for single user
```
Connect-MgGraph -Scopes IdentityRiskEvent.Read.All,	IdentityRiskyUser.ReadWrite.All

$userid = '2aeedc43-2ad4-4a18-b78e-5b4511076146'
 
 $body = @"
{
    "userIds": [
    "$userid"
    ]
}
"@

Invoke-MgBetaDismissRiskyUser -BodyParameter $body
```

## Look at current potential impact.

## Setting up Conditional Access Policies

