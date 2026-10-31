<#PSScriptInfo
.VERSION 2026.10
.GUID bb8c8fbf-d7ce-43a5-953f-c8e7ded1d082
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
Pulls audit events about directory roles and their members: role membership and PIM changes, changes made to admin accounts, and changes made by admin accounts.
url: List directoryAudits - https://learn.microsoft.com/en-us/graph/api/directoryaudit-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports role-related audit events.
.DESCRIPTION
    Replaces Roles\auditRoleMembershipChanges, PIM\auditPIMRoleChanges, getAADChangesToGlobalAdmins,
    getAADChangesbyGlobalAdmins and Security\GatherRoleMemberChanges.
.PARAMETER Report
    RoleChanges - every RoleManagement audit event (role and PIM changes).
    ChangesToAdmins - events where an admin account was the target.
    ChangesByAdmins - events an admin account started.
.PARAMETER Days
    How many days back to search. Audit logs keep 30 days.
.EXAMPLE
    .\Get-RoleAuditEvents.ps1 -Environment Global -Report ChangesByAdmins -Days 7
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("RoleChanges", "ChangesToAdmins", "ChangesByAdmins")][string]$Report = "RoleChanges",
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

function Get-AdminMembers {
    "$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal,roleDefinition" | Get-GraphPage |
        Where-Object { $_.roleDefinition.isPrivileged -and $_.principal.'@odata.type' -eq "#microsoft.graph.user" } |
        Select-Object @{ n = "id"; e = { $_.principal.id } }, @{ n = "userPrincipalName"; e = { $_.principal.userPrincipalName } } -Unique
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
$events = switch ($Report) {
    "RoleChanges" {
        "$($audits)?`$filter=category eq 'RoleManagement' and activityDateTime ge $since" | Get-GraphPage
    }
    "ChangesToAdmins" {
        Get-AdminMembers | ForEach-Object { "$($audits)?`$filter=targetResources/any(t:t/id eq '$($_.id)') and activityDateTime ge $since" | Get-GraphPage }
    }
    "ChangesByAdmins" {
        Get-AdminMembers | ForEach-Object { "$($audits)?`$filter=initiatedBy/user/id eq '$($_.id)' and activityDateTime ge $since" | Get-GraphPage }
    }
}
$file = Join-Path $Path "entra_role_audit_$Report.csv"
$events | Format-AuditEvent | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
