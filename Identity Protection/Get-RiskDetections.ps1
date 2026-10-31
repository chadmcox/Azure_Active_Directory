<#PSScriptInfo
.VERSION 2026.10
.GUID 656b4e0d-9d95-44b9-9cd9-f03741f3b514
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
Exports Identity Protection risk detections for users (such as leaked credentials, unfamiliar sign-in properties and impossible travel) for a set number of days, for triage and investigation.
url: What are risk detections - https://learn.microsoft.com/en-us/entra/id-protection/concept-identity-protection-risks
url: List riskDetections - https://learn.microsoft.com/en-us/graph/api/riskdetection-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports user risk detections.
.DESCRIPTION
    Needs Microsoft Entra ID P2 for full detail. Use Get-RiskyServicePrincipals.ps1 for workload identities.
.EXAMPLE
    .\Get-RiskDetections.ps1 -Environment Global -Days 30
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 30,
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

Connect-Cloud -Scopes "IdentityRiskEvent.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_risk_detections.csv"
"$script:Graph/identityProtection/riskDetections?`$filter=detectedDateTime ge $since" | Get-GraphPage |
    Select-Object detectedDateTime, userPrincipalName, riskEventType, riskLevel, riskState, riskDetail, detectionTimingType, source, activity, ipAddress,
        @{ n = "Location"; e = { "$($_.location.city), $($_.location.countryOrRegion)" } }, tokenIssuerType, correlationId, id |
    Sort-Object detectedDateTime -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
