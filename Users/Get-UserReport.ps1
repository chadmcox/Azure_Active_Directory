<#PSScriptInfo
.VERSION 2026.10
.GUID 2efbc85b-556a-4d9b-95b0-7b7937730c53
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
Reports every member user with sign-in activity, password age and hybrid sync state, and flags stale accounts, old passwords and synced users that stopped syncing.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
#>
<#
.SYNOPSIS
    Exports a report of member users.
.DESCRIPTION
    Replaces create-AADMGUserReport, create-AADUserSigninreport, find-AADMGUsersStaleLastSignIn,
    find-AADMGUserStalePWD, find-usersnotsyncing, Get-EntraHybridUserPasswordChange, getAADUserSignons,
    Backup\export-Users and GCC\exportGCCAADUsers (pick USGov or USGovDoD for government clouds).
.PARAMETER StaleDays
    Days without any sign-in before the Stale column is true. Default 90.
.PARAMETER PasswordAgeDays
    Days since the last password change before the OldPassword column is true. Default 365.
.PARAMETER IncludeDisabled
    Include disabled accounts.
.EXAMPLE
    .\Get-UserReport.ps1 -Environment USGov -StaleDays 60
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$StaleDays = 90,
    [int]$PasswordAgeDays = 365,
    [switch]$IncludeDisabled,
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

function Get-DaysSince {
    param($Date)
    if ($Date) { [int]((Get-Date) - [datetime]$Date).TotalDays }
}

function Format-User {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $lastActivity = @($User.signInActivity.lastSignInDateTime, $User.signInActivity.lastNonInteractiveSignInDateTime) |
            Where-Object { $_ } | ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1
        $User | Select-Object id, displayName, userPrincipalName, mail, jobTitle, department, accountEnabled, createdDateTime,
            onPremisesSyncEnabled, onPremisesDomainName, onPremisesSamAccountName, onPremisesLastSyncDateTime,
            lastPasswordChangeDateTime, refreshTokensValidFromDateTime, signInSessionsValidFromDateTime,
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "LastSuccessfulSignInDateTime"; e = { $_.signInActivity.lastSuccessfulSignInDateTime } },
            @{ n = "DaysSinceLastSignIn"; e = { Get-DaysSince $lastActivity } },
            @{ n = "PasswordAgeDays"; e = { Get-DaysSince $_.lastPasswordChangeDateTime } },
            @{ n = "DaysSinceLastSync"; e = { if ($_.onPremisesSyncEnabled) { Get-DaysSince $_.onPremisesLastSyncDateTime } } },
            @{ n = "Stale"; e = { [datetime]$_.createdDateTime -lt (Get-Date).AddDays(-$StaleDays) -and (-not $lastActivity -or $lastActivity -lt (Get-Date).AddDays(-$StaleDays)) } },
            @{ n = "OldPassword"; e = { $_.lastPasswordChangeDateTime -and [datetime]$_.lastPasswordChangeDateTime -lt (Get-Date).AddDays(-$PasswordAgeDays) } },
            @{ n = "NotSyncing"; e = { $_.onPremisesSyncEnabled -and [datetime]$_.onPremisesLastSyncDateTime -lt (Get-Date).AddDays(-7) } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "AuditLog.Read.All"

$filter = if ($IncludeDisabled) { "userType eq 'Member'" } else { "userType eq 'Member' and accountEnabled eq true" }
$file = Join-Path $Path "entra_users.csv"
Write-Host "Getting users"
"$script:Graph/users?`$filter=$filter&`$select=id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled,createdDateTime,onPremisesSyncEnabled,onPremisesDomainName,onPremisesSamAccountName,onPremisesLastSyncDateTime,lastPasswordChangeDateTime,refreshTokensValidFromDateTime,signInSessionsValidFromDateTime,signInActivity,identityParentId" |
    Get-GraphPage | Where-Object { -not $_.identityParentId } | Format-User | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
