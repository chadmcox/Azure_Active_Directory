<#PSScriptInfo
.VERSION 2026.10
.GUID a15cbc95-1f33-48e9-aaa8-d668340871e4
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
Exports Microsoft Defender XDR and Entra ID Protection security alerts from the last set number of days.
url: List alerts_v2 - https://learn.microsoft.com/en-us/graph/api/security-list-alerts_v2?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports security alerts.
.DESCRIPTION
    Replaces Security Alerts\gather-graphSecurityAlerts, which used the retired legacy alerts API.
.EXAMPLE
    .\Get-SecurityAlerts.ps1 -Environment Global -Days 30
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

Connect-Cloud -Scopes "SecurityAlert.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "security_alerts.csv"
"$script:Graph/security/alerts_v2?`$filter=createdDateTime ge $since" | Get-GraphPage |
    Select-Object createdDateTime, title, severity, status, classification, determination, serviceSource, detectionSource, category,
        @{ n = "Users"; e = { ($_.evidence | Where-Object { $_.userAccount } | ForEach-Object { $_.userAccount.userPrincipalName }) -join ";" } },
        @{ n = "MitreTechniques"; e = { $_.mitreTechniques -join ";" } },
        incidentWebUrl, alertWebUrl, id |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
