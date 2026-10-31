<#PSScriptInfo
.VERSION 2026.10
.GUID 6c82a44a-c829-4491-811f-7006632ece61
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
Pulls high-impact audit events, like federation and sync changes, permanent role assignments, new credentials on apps and Conditional Access changes, into one CSV.
url: Microsoft Entra audit log activity reference - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/reference-audit-activities
#>
<#
.SYNOPSIS
    Exports critical directory audit events.
.DESCRIPTION
    Replaces Security\gatherAzureADAuditLogs.
.PARAMETER Activities
    The audit activity names to search for. The default list covers the old script.
.EXAMPLE
    .\Get-CriticalAuditEvents.ps1 -Environment Global -Days 30
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 30,
    [string[]]$Activities = @(
        "Enable passthrough authentication", "Set DirSync feature", "Register connector", "Set domain authentication",
        "Set federation settings on domain", "Enable password writeback for directory", "Set password policy",
        "Add member to role outside of PIM (permanent)", "Add member to role", "Add role definition",
        "Add service principal credentials", "Add app role assignment to service principal", "Add app role assignment grant to user",
        "Add conditional access policy", "Update conditional access policy", "Delete conditional access policy"),
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

Connect-Cloud -Scopes "AuditLog.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_critical_audit_events.csv"
$Activities | ForEach-Object {
    "$script:Graph/auditLogs/directoryAudits?`$filter=activityDisplayName eq '$_' and activityDateTime ge $since" | Get-GraphPage
} | Select-Object activityDateTime, category, activityDisplayName, result,
        @{ n = "InitiatedBy"; e = { if ($_.initiatedBy.user.userPrincipalName) { $_.initiatedBy.user.userPrincipalName } else { $_.initiatedBy.app.displayName } } },
        @{ n = "IpAddress"; e = { $_.initiatedBy.user.ipAddress } },
        @{ n = "Target"; e = { ($_.targetResources | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
        @{ n = "Changes"; e = { ($_.targetResources.modifiedProperties | ForEach-Object { "$($_.displayName)=$($_.newValue)" }) -join "; " } } |
    Sort-Object activityDateTime -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
