<#PSScriptInfo
.VERSION 2026.10
.GUID d66de744-81be-481c-81ba-a352a1d366f4
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
Dismisses user risk that is older than a set number of days for the chosen risk levels. Runs interactively or as an Azure Automation runbook with a managed identity.
url: riskyUser: dismiss - https://learn.microsoft.com/en-us/graph/api/riskyuser-dismiss?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Dismisses old user risk.
.DESCRIPTION
    Replaces dismiss-IdentityProtectionRiskyUsers and Maintenance Task\runbook-dismissAIPRiskyUsers.
.PARAMETER OlderThanDays
    Only dismiss risk last updated more than this many days ago. Default 30.
.PARAMETER RiskLevel
    Risk levels to dismiss. Default low and medium.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Dismiss-RiskyUsers.ps1 -Environment Global -OlderThanDays 120 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$OlderThanDays = 30,
    [ValidateSet("low", "medium", "high")][string[]]$RiskLevel = @("low", "medium"),
    [switch]$Identity,
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

function Dismiss-Risk {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$RiskyUser)
    process {
        $action = if ($PSCmdlet.ShouldProcess($RiskyUser.userPrincipalName, "Dismiss $($RiskyUser.riskLevel) risk")) {
            $body = @{ userIds = @($RiskyUser.id) } | ConvertTo-Json
            Invoke-MgGraphRequest -Uri "$script:Graph/identityProtection/riskyUsers/dismiss" -Method POST -Body $body -ContentType "application/json"
            "Dismissed"
        } else { "WhatIf" }
        $RiskyUser | Select-Object id, userPrincipalName, riskLevel, riskDetail, riskLastUpdatedDateTime, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "IdentityRiskyUser.ReadWrite.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$OlderThanDays)
$results = "$script:Graph/identityProtection/riskyUsers?`$filter=riskState eq 'atRisk'" | Get-GraphPage |
    Where-Object { $_.riskLevel -in $RiskLevel -and [datetime]$_.riskLastUpdatedDateTime -lt $cutoff } |
    Dismiss-Risk
$results | Format-Table userPrincipalName, riskLevel, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_risky_users_dismissed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
