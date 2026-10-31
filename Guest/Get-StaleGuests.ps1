<#PSScriptInfo
.VERSION 2026.10
.GUID d793fd69-9e45-406b-b75d-12f0b7a1f3f9
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
Finds guests that have not signed in for a set number of days and guests that never accepted their invitation, with sponsors and the reason each is stale.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
#>
<#
.SYNOPSIS
    Creates a stale guest report.
.DESCRIPTION
    Review the CSV (ask sponsors if needed), remove any guests to keep, then pass it to
    Remove-StaleGuests.ps1 -CsvPath. Guests invited inside the window are never stale.
.PARAMETER Days
    Days without a sign-in for accepted guests. Default 90.
.PARAMETER PendingDays
    Days an invitation can stay unaccepted. Default 30.
.EXAMPLE
    .\Get-StaleGuests.ps1 -Environment Global -Days 90 -PendingDays 30
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 90,
    [int]$PendingDays = 30,
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

function Get-StaleReason {
    param($Guest)
    if ($Guest.externalUserState -eq "PendingAcceptance") {
        if ([datetime]$Guest.externalUserStateChangeDateTime -lt (Get-Date).AddDays(-$PendingDays)) { return "PendingAcceptance" }
        return
    }
    $cutoff = (Get-Date).AddDays(-$Days)
    $recent = @($Guest.signInActivity.lastSignInDateTime, $Guest.signInActivity.lastNonInteractiveSignInDateTime, $Guest.signInActivity.lastSuccessfulSignInDateTime, $Guest.createdDateTime) |
        Where-Object { $_ -and [datetime]$_ -ge $cutoff }
    if (-not $recent) { "Inactive" }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $reason = Get-StaleReason -Guest $Guest
        if (-not $reason) { return }
        $Guest | Select-Object id, displayName, userPrincipalName, mail, accountEnabled, createdDateTime, externalUserState, externalUserStateChangeDateTime,
            @{ n = "StaleReason"; e = { $reason } },
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "Sponsors"; e = { ($_.sponsors | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "AuditLog.Read.All"

$file = Join-Path $Path "entra_stale_guests.csv"
Write-Host "Getting guests"
"$script:Graph/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,mail,accountEnabled,createdDateTime,externalUserState,externalUserStateChangeDateTime,signInActivity&`$expand=sponsors(`$select=id,displayName,userPrincipalName)" |
    Get-GraphPage | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
