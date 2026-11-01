<#PSScriptInfo
.VERSION 2026.10
.GUID 224038f2-f0b8-437a-a6b1-2502ba74002c
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
Pulls every role membership and PIM change (RoleManagement audit events) from the audit log for a set number of days.
url: List directoryAudits - https://learn.microsoft.com/en-us/graph/api/directoryaudit-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports every role membership and PIM change (RoleManagement audit events).
.DESCRIPTION
    Replaces Roles\auditRoleMembershipChanges and PIM\auditPIMRoleChanges. Audit logs keep 30 days.
.PARAMETER Days
    How many days back to search.
.EXAMPLE
    .\Get-RoleChanges.ps1 -Environment Global -Days 7
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

function Format-AuditEvent {
    param([Parameter(ValueFromPipeline)]$AuditEvent)
    process {
        $AuditEvent | Select-Object activityDateTime, category, activityDisplayName, result,
            @{ n = "InitiatedBy"; e = { if ($_.initiatedBy.user.userPrincipalName) { $_.initiatedBy.user.userPrincipalName } else { $_.initiatedBy.app.displayName } } },
            @{ n = "Target"; e = { ($_.targetResources | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "Role"; e = { (($_.targetResources.modifiedProperties | Where-Object { $_.displayName -eq "Role.DisplayName" }).newValue) -replace '"', "" } },
            @{ n = "Group"; e = { (($_.targetResources.modifiedProperties | Where-Object { $_.displayName -eq "Group.DisplayName" }).newValue) -replace '"', "" } }
    }
}

Connect-Cloud -Scopes "AuditLog.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$audits = "$script:Graph/auditLogs/directoryAudits"
$events = "$($audits)?`$filter=category eq 'RoleManagement' and activityDateTime ge $since" | Get-GraphPage
$file = Join-Path $Path "entra_rolechanges.csv"
$events | Format-AuditEvent | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
