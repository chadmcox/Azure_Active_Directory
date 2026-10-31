<#PSScriptInfo
.VERSION 2026.10
.GUID 157f78fb-d655-4ab4-b364-21eaa5be9601
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
Finds member accounts that have not signed in (interactively or non-interactively) for a set number of days and says how to remediate each one: disable in Entra for cloud-only accounts, disable in Active Directory for synced accounts.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
#>
<#
.SYNOPSIS
    Creates a stale user report.
.DESCRIPTION
    Review the CSV, remove any accounts to keep, then pass it to Disable-StaleUsers.ps1 -CsvPath.
    Accounts created inside the window are never stale. Needs Microsoft Entra ID P1 for sign-in activity.
.PARAMETER Days
    Days without any sign-in. Default 90.
.EXAMPLE
    .\Get-StaleUsers.ps1 -Environment Global -Days 90
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 90,
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

function Get-LastActivity {
    param($User)
    @($User.signInActivity.lastSignInDateTime, $User.signInActivity.lastNonInteractiveSignInDateTime, $User.signInActivity.lastSuccessfulSignInDateTime) |
        Where-Object { $_ } | ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $last = Get-LastActivity -User $User
        if ((-not $User.createdDateTime -or [datetime]$User.createdDateTime -lt $cutoff) -and (-not $last -or $last -lt $cutoff)) {
            $User | Select-Object id, displayName, userPrincipalName, accountEnabled, createdDateTime, onPremisesSyncEnabled, onPremisesSamAccountName, lastPasswordChangeDateTime,
                @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
                @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
                @{ n = "DaysSinceLastActivity"; e = { if ($last) { [int]((Get-Date) - $last).TotalDays } else { "Never" } } },
                @{ n = "Licenses"; e = { @($_.assignedLicenses).Count } },
                @{ n = "Remediation"; e = { if ($_.onPremisesSyncEnabled) { "Disable in Active Directory" } else { "Disable-StaleUsers.ps1" } } }
        }
    }
}

Connect-Cloud -Scopes "User.Read.All", "AuditLog.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
$file = Join-Path $Path "entra_stale_users.csv"
Write-Host "Getting enabled member accounts"
"$script:Graph/users?`$filter=userType eq 'Member' and accountEnabled eq true&`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,onPremisesSyncEnabled,onPremisesSamAccountName,lastPasswordChangeDateTime,assignedLicenses,signInActivity&`$top=999" |
    Get-GraphPage | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
