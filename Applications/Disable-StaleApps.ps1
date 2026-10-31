<#PSScriptInfo
.VERSION 2026.10
.GUID 697dc88b-b81e-42e4-84b1-c6957b8c4439
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
Disables enterprise apps (service principals) with no sign-in activity for a set number of days, either from a reviewed Get-StaleApps.ps1 report or by finding them live. Disabling blocks sign-ins and tokens but keeps the app, so it can be turned back on. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Disable user sign-in for an application - https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/disable-user-sign-in-portal
#>
<#
.SYNOPSIS
    Disables stale enterprise apps.
.DESCRIPTION
    Every app is checked again before it is disabled, so an app that signed in after the report was
    made is skipped. Microsoft first-party apps and managed identities are never touched. To undo,
    set accountEnabled back to true on the service principal.
.PARAMETER CsvPath
    A reviewed Get-StaleApps.ps1 report. Without it, stale apps are found live.
.PARAMETER Days
    Days without any sign-in activity. Default 90.
.PARAMETER MaxRemovals
    Stop after this many apps, as a safety limit. Default 10.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Disable-StaleApps.ps1 -Environment Global -CsvPath .\entra_stale_apps.csv -WhatIf
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
    $select = "id,appId,displayName,accountEnabled,servicePrincipalType,appOwnerOrganizationId,createdDateTime"
    if ($CsvPath) {
        Import-Csv $CsvPath | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/servicePrincipals/$($_.id)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$select=$select" | Get-GraphPage
    }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$App)
    process {
        $last = $lastSignIns[$App.appId].lastSignInActivity.lastSignInDateTime
        $stale = (-not $App.createdDateTime -or [datetime]$App.createdDateTime -lt $cutoff) -and (-not $last -or [datetime]$last -lt $cutoff)
        $allowed = $App.accountEnabled -and $App.servicePrincipalType -eq "Application" -and $App.appOwnerOrganizationId -ne $microsoftTenantId
        if ($stale -and $allowed) { $App | Select-Object *, @{ n = "LastSignInDateTime"; e = { $last } } }
    }
}

function Disable-App {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$App)
    process {
        $action = if ($PSCmdlet.ShouldProcess($App.displayName, "Disable enterprise app")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/servicePrincipals/$($App.id)" -Method PATCH -Body (@{ accountEnabled = $false } | ConvertTo-Json) -ContentType "application/json"
            "Disabled"
        } else { "WhatIf" }
        $App | Select-Object id, appId, displayName, createdDateTime, LastSignInDateTime, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Application.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
$cutoff = (Get-Date).AddDays(-$Days)
$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { $lastSignIns = @{} }

$results = Get-Candidates | Where-Object { $_.'@odata.type' -notmatch 'agent' } | Select-Stale | Select-Object -First $MaxRemovals | Disable-App
$results | Format-Table displayName, LastSignInDateTime, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_apps_disabled.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
