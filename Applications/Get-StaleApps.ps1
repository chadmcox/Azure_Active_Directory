<#PSScriptInfo
.VERSION 2026.10
.GUID d02cad3c-5e5e-4134-bbd2-0888d1b2b002
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
Finds enabled enterprise apps with no sign-in activity (user or app-only) for a set number of days, plus apps Entra recommends removing as unused, with owners and credentials so owners can be asked before the app is disabled.
url: Remove unused applications recommendation - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/recommendation-remove-unused-apps
url: servicePrincipalSignInActivity - https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipalsigninactivity?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a stale enterprise app report.
.DESCRIPTION
    Review the CSV, check with the owners, remove any apps to keep, then pass it to
    Disable-StaleApps.ps1 -CsvPath. Microsoft first-party apps and managed identities are left out.
    Apps created inside the window are never stale. Needs Microsoft Entra ID P1 for sign-in activity.
.PARAMETER Days
    Days without any sign-in activity. Default 90.
.EXAMPLE
    .\Get-StaleApps.ps1 -Environment Global -Days 90
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

function Get-UnusedAppRecommendations {
    "$script:Graph/directory/recommendations" | Get-GraphPage |
        Where-Object { $_.status -eq "active" -and $_.displayName -eq "Remove unused applications" } |
        ForEach-Object { "$script:Graph/directory/recommendations/$($_.id)/impactedResources" | Get-GraphPage } |
        Where-Object { $_.status -eq "active" } | Select-Object id, addedDateTime
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$App)
    process {
        $last = $lastSignIns[$App.appId].lastSignInActivity.lastSignInDateTime
        $inactive = (-not $App.createdDateTime -or [datetime]$App.createdDateTime -lt $cutoff) -and (-not $last -or [datetime]$last -lt $cutoff)
        $recommended = $unusedApps.ContainsKey($App.appId)
        if (-not ($inactive -or $recommended)) { return }
        $App | Select-Object id, appId, displayName, publisherName, accountEnabled, createdDateTime, preferredSingleSignOnMode, appRoleAssignmentRequired,
            @{ n = "StaleReason"; e = { (@(if ($inactive) { "NoSignIn" }; if ($recommended) { "EntraRecommendation" })) -join ";" } },
            @{ n = "LastSignInDateTime"; e = { $last } },
            @{ n = "DaysSinceLastSignIn"; e = { if ($last) { [int]((Get-Date) - [datetime]$last).TotalDays } else { "Never" } } },
            @{ n = "ValidCredentials"; e = { @(@($_.keyCredentials) + @($_.passwordCredentials) | Where-Object { $_ -and [datetime]$_.endDateTime -gt (Get-Date) }).Count } },
            @{ n = "Owners"; e = { ($_.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "NotificationEmailAddresses"; e = { $_.notificationEmailAddresses -join ";" } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "AuditLog.Read.All", "DirectoryRecommendations.Read.All"

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
$cutoff = (Get-Date).AddDays(-$Days)

Write-Host "Getting service principal sign-in activity"
$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { $lastSignIns = @{} }
Write-Host "Getting Entra recommendations for unused apps"
$unusedApps = @(Get-UnusedAppRecommendations) | Group-Object id -AsHashTable -AsString
if (-not $unusedApps) { $unusedApps = @{} }

$file = Join-Path $Path "entra_stale_apps.csv"
Write-Host "Getting enabled enterprise apps"
"$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$select=id,appId,displayName,publisherName,accountEnabled,createdDateTime,preferredSingleSignOnMode,appRoleAssignmentRequired,keyCredentials,passwordCredentials,notificationEmailAddresses,appOwnerOrganizationId&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage |
    Where-Object { $_.appOwnerOrganizationId -ne $microsoftTenantId -and $_.'@odata.type' -notmatch 'agent' } |
    Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
