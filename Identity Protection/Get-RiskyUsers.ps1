<#PSScriptInfo
.VERSION 2026.10
.GUID 3bb772e0-24c9-4a4e-b4fa-c54ef9babe44
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
Reports users Identity Protection currently marks as at risk, with risk level, when the risk was last updated and whether the user changed their password since.
url: List riskyUsers - https://learn.microsoft.com/en-us/graph/api/riskyuser-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports at-risk users.
.DESCRIPTION
    Replaces export-IdentityProtectionAllRiskyUsers and Backup\export-RiskyUsers. Use Dismiss-RiskyUsers.ps1
    to clear old risk after reviewing.
.EXAMPLE
    .\Get-RiskyUsers.ps1 -Environment Global
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

function Add-UserDetail {
    param([Parameter(ValueFromPipeline)]$RiskyUser)
    process {
        $user = try { Invoke-MgGraphRequest -Uri "$script:Graph/users/$($RiskyUser.id)?`$select=accountEnabled,lastPasswordChangeDateTime,onPremisesSyncEnabled,signInActivity" -OutputType PSObject -ErrorAction Stop } catch { $null }
        $RiskyUser | Select-Object id, userPrincipalName, userDisplayName, riskLevel, riskState, riskDetail, riskLastUpdatedDateTime, isDeleted,
            @{ n = "DaysAtRisk"; e = { [int]((Get-Date) - [datetime]$_.riskLastUpdatedDateTime).TotalDays } },
            @{ n = "AccountEnabled"; e = { $user.accountEnabled } },
            @{ n = "OnPremisesSyncEnabled"; e = { [bool]$user.onPremisesSyncEnabled } },
            @{ n = "LastPasswordChangeDateTime"; e = { $user.lastPasswordChangeDateTime } },
            @{ n = "PasswordChangedSinceRisk"; e = { $user.lastPasswordChangeDateTime -and [datetime]$user.lastPasswordChangeDateTime -gt [datetime]$_.riskLastUpdatedDateTime } },
            @{ n = "LastSignInDateTime"; e = { $user.signInActivity.lastSignInDateTime } }
    }
}

Connect-Cloud -Scopes "IdentityRiskyUser.Read.All", "User.Read.All", "AuditLog.Read.All"

$file = Join-Path $Path "entra_risky_users.csv"
"$script:Graph/identityProtection/riskyUsers?`$filter=riskState eq 'atRisk'" | Get-GraphPage |
    Add-UserDetail | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
