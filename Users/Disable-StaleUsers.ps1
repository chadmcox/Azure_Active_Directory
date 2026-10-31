<#PSScriptInfo
.VERSION 2026.10
.GUID 6c701f82-8b7b-4b9a-ab5d-76ac39b43a90
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
Disables cloud-only member accounts that have not signed in for a set number of days, either from a reviewed Get-StaleUsers.ps1 report or by finding them live. Runs interactively or as an Azure Automation runbook with a managed identity.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
#>
<#
.SYNOPSIS
    Disables stale cloud-only users.
.DESCRIPTION
    Every account is checked again before it is disabled, so a user who signed in after the report was
    made is skipped. Synced accounts are skipped; disable those in Active Directory.
.PARAMETER CsvPath
    A reviewed Get-StaleUsers.ps1 report. Without it, stale users are found live.
.PARAMETER Days
    Days without any sign-in. Default 90.
.PARAMETER MaxRemovals
    Stop after this many accounts, as a safety limit. Default 10.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Disable-StaleUsers.ps1 -Environment Global -CsvPath .\entra_stale_users.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$Days = 90,
    [int]$MaxRemovals = 10,
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

function Get-Candidates {
    $select = "id,userPrincipalName,accountEnabled,createdDateTime,onPremisesSyncEnabled,signInActivity,identityParentId"
    if ($CsvPath) {
        Import-Csv $CsvPath | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_.id)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/users?`$filter=userType eq 'Member' and accountEnabled eq true&`$select=$select" | Get-GraphPage
    }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $recent = @($User.signInActivity.lastSignInDateTime, $User.signInActivity.lastNonInteractiveSignInDateTime, $User.signInActivity.lastSuccessfulSignInDateTime, $User.createdDateTime) |
            Where-Object { $_ -and [datetime]$_ -ge $cutoff }
        if ($User.accountEnabled -and -not $User.onPremisesSyncEnabled -and -not $recent) { $User }
    }
}

function Disable-User {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $action = if ($PSCmdlet.ShouldProcess($User.userPrincipalName, "Disable account")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($User.id)" -Method PATCH -Body (@{ accountEnabled = $false } | ConvertTo-Json) -ContentType "application/json"
            "Disabled"
        } else { "WhatIf" }
        $User | Select-Object id, userPrincipalName, createdDateTime,
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$results = Get-Candidates | Where-Object { -not $_.identityParentId } | Select-Stale | Select-Object -First $MaxRemovals | Disable-User
$results | Format-Table userPrincipalName, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_users_disabled.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
