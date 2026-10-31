<#PSScriptInfo
.VERSION 2026.10
.GUID d0a35948-bc19-4f45-aee3-1b61c0441416
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
Lists Microsoft Entra health monitoring alerts, such as spikes in MFA failures, Conditional Access blocks or device compliance failures, with their state and impact.
url: What is Microsoft Entra health monitoring - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-microsoft-entra-health
url: List alerts (health monitoring) - https://learn.microsoft.com/en-us/graph/api/healthmonitoring-healthmonitoringroot-list-alerts?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports Microsoft Entra health monitoring alerts.
.DESCRIPTION
    Needs Microsoft Entra ID P1. Alerts are kept for 30 days.
.EXAMPLE
    .\Get-HealthAlerts.ps1 -Environment Global
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

Connect-Cloud -Scopes "HealthMonitoringAlert.Read.All"

$file = Join-Path $Path "entra_health_alerts.csv"
"$script:Graph/reports/healthMonitoring/alerts" | Get-GraphPage |
    Select-Object createdDateTime, alertType, scenario, category, state, id,
        @{ n = "Impact"; e = { ($_.enrichment.impacts | ForEach-Object { "$($_.resourceType): $($_.impactedCount)" }) -join ";" } },
        @{ n = "Signals"; e = { ($_.signals.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ";" } } |
    Sort-Object createdDateTime -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
