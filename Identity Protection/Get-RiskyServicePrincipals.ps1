<#PSScriptInfo
.VERSION 2026.10
.GUID 3fe5e2c1-8b05-4be4-a32f-878d156ee2ce
.AUTHOR Chad Cox
    https://blogs.technet.microsoft.com/chadcox/
    https://github.com/chadmcox
.COMPANYNAME
.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample Code..
.description
Lists workload identities (service principals) that Identity Protection marks as risky, with their risk detections, so compromised apps can be investigated.
url: Securing workload identities with Identity Protection - https://learn.microsoft.com/en-us/entra/id-protection/concept-workload-identity-risk
url: List riskyServicePrincipals - https://learn.microsoft.com/en-us/graph/api/identityprotectionroot-list-riskyserviceprincipals?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports risky service principals and their detections.
.DESCRIPTION
    Needs Microsoft Entra Workload ID Premium for full detail.
.EXAMPLE
    .\Get-RiskyServicePrincipals.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$Path = "$env:USERPROFILE\Downloads"
)

function Connect-Cloud {
    param([string[]]$Scopes, [switch]$Identity)
    $clouds = "Global", "USGov", "USGovDoD"
    if (-not $script:Environment) {
        Get-MgEnvironment | Where-Object { $_.Name -in $clouds } | Select-Object Name, GraphEndpoint | Out-Host
        $answer = Read-Host "Type the cloud to connect to (Global, USGov, USGovDoD). Press Enter for Global"
        $script:Environment = if ($answer -in $clouds) { $answer } else { "Global" }
    }
    if ($Identity) {
        Connect-MgGraph -Identity -Environment $script:Environment -NoWelcome
    } else {
        Connect-MgGraph -Scopes $Scopes -Environment $script:Environment -NoWelcome
    }
    $script:Graph = "$((Get-MgEnvironment -Name $script:Environment).GraphEndpoint)/beta"
}

function Get-GraphPage {
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Uri, [switch]$Eventual)
    process {
        $headers = if ($Eventual) { @{ ConsistencyLevel = "eventual" } } else { @{} }
        do {
            $response = Invoke-MgGraphRequest -Uri $Uri -Method GET -Headers $headers -OutputType PSObject -ErrorAction Stop
            if ($response.PSObject.Properties.Name -contains "value") { $response.value } else { $response }
            $Uri = $response.'@odata.nextLink'
        } while ($Uri)
    }
}

Connect-Cloud -Scopes "IdentityRiskyServicePrincipal.Read.All", "IdentityRiskEvent.Read.All"

"$script:Graph/identityProtection/riskyServicePrincipals" | Get-GraphPage |
    Select-Object displayName, appId, id, servicePrincipalType, isEnabled, riskLevel, riskState, riskDetail, riskLastUpdatedDateTime |
    Export-Csv (Join-Path $Path "entra_risky_service_principals.csv") -NoTypeInformation
"$script:Graph/identityProtection/servicePrincipalRiskDetections" | Get-GraphPage |
    Select-Object detectedDateTime, servicePrincipalDisplayName, appId, riskEventType, riskLevel, riskState, activity, ipAddress, detectionTimingType, source,
        @{ n = "KeyIds"; e = { $_.keyIds -join ";" } } |
    Export-Csv (Join-Path $Path "entra_service_principal_risk_detections.csv") -NoTypeInformation
Write-Host "Results: $Path\entra_risky_service_principals.csv and entra_service_principal_risk_detections.csv"
