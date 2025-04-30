# Microsoft.Graph PowerShell examples.
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
### Research a user's risk
```
Get-MgBetaRiskDetection -filter "UserPrincipalName eq 'carlee.levine@blue.chadcolabs.us'" | fl
# example result
Activity             : signin
ActivityDateTime     : 4/15/2025 4:22:10 PM
AdditionalInfo       : [{"Key":"userAgent","Value":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"},{"Key":"mitreTechniques","Value":"T1090.003,T1078"}]
CorrelationId        : dfb4f731-4bdc-4b97-a015-682bf8a542c5
DetectedDateTime     : 4/15/2025 4:22:10 PM
DetectionTimingType  : realtime
IPAddress            : 2a0e:4005:1002:ffff:185:40:4:20
Id                   : 41efcebea8d7b05e656d3b7cd68d11ff7c9c3647f9b49a709d70e3cc8cd7658b
LastUpdatedDateTime  : 4/15/2025 4:23:47 PM
Location             : Microsoft.Graph.Beta.PowerShell.Models.MicrosoftGraphSignInLocation
MitreTechniqueId     : T1090.003
RequestId            : 030b8d7f-e8ed-4838-941a-e68265506b00
RiskDetail           : userPassedMFADrivenByRiskBasedPolicy
RiskEventType        : anonymizedIPAddress
RiskLevel            : medium
RiskState            : remediated
RiskType             : anonymizedIPAddress
Source               : IdentityProtection
TokenIssuerType      : AzureAD
UserDisplayName      : Carlee Levine
UserId               : 35114a0d-c71a-4de0-91d2-d7a3009838c6
UserPrincipalName    : Carlee.Levine@blue.chadcolabs.us
AdditionalProperties : {[homeTenantId, 4a7f2f53-02ba-4ead-b55f-d917f7ea95c0], [userType, member], [crossTenantAccessType, none]}
```
