<#PSScriptInfo
.VERSION 2026.10
.GUID c4ad36e1-6519-4844-87d1-14066f70c236
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
Deletes stale cloud groups that are empty and not used anywhere (not in Conditional Access, not role-assignable, no licenses, no app assignments), after saving a JSON backup of each group. Works from a reviewed Get-StaleGroups.ps1 report or finds them live. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Delete group - https://learn.microsoft.com/en-us/graph/api/group-delete?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Deletes empty, unused cloud groups.
.DESCRIPTION
    Every group is checked again before deletion. Synced and dynamic groups are never deleted.
    Microsoft 365 groups can be restored for 30 days; security groups are deleted permanently, so
    keep the JSON backup this script writes.
.PARAMETER CsvPath
    A reviewed Get-StaleGroups.ps1 report. Without it, stale groups are found live.
.PARAMETER Days
    Minimum group age. Default 180.
.PARAMETER MaxRemovals
    Stop after this many groups, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleGroups.ps1 -Environment Global -CsvPath .\entra_stale_groups.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$Days = 180,
    [int]$MaxRemovals = 25,
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
    $select = "id,displayName,description,mailNickname,mail,groupTypes,securityEnabled,mailEnabled,createdDateTime,onPremisesSyncEnabled,isAssignableToRole,assignedLicenses"
    if ($CsvPath) {
        Import-Csv $CsvPath | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($_.id)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/groups?`$select=$select" | Get-GraphPage
    }
}

function Select-Removable {
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        if ($Group.onPremisesSyncEnabled -or $Group.isAssignableToRole -or $Group.assignedLicenses -or $caGroups.ContainsKey($Group.id)) { return }
        if ($Group.groupTypes -contains "DynamicMembership" -or ($Group.createdDateTime -and [datetime]$Group.createdDateTime -ge $cutoff)) { return }
        $members = [int](Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($Group.id)/transitiveMembers/`$count" -Headers @{ ConsistencyLevel = "eventual" })
        if ($members -gt 0) { return }
        $assignments = @("$script:Graph/groups/$($Group.id)/appRoleAssignments" | Get-GraphPage)
        if ($assignments) { return }
        $Group
    }
}

function Remove-Group {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        $action = if ($PSCmdlet.ShouldProcess($Group.displayName, "Delete empty group")) {
            $owners = "$script:Graph/groups/$($Group.id)/owners?`$select=id,displayName,userPrincipalName" | Get-GraphPage | Select-Object id, displayName, userPrincipalName
            $Group | Select-Object *, @{ n = "owners"; e = { $owners } } | ConvertTo-Json -Depth 5 |
                Out-File (Join-Path $backupFolder "$($Group.id).json") -WhatIf:$false
            Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($Group.id)" -Method DELETE
            "Deleted"
        } else { "WhatIf" }
        $Group | Select-Object id, displayName, mail, createdDateTime,
            @{ n = "Type"; e = { if ($_.groupTypes -contains "Unified") { "Microsoft 365" } elseif ($_.securityEnabled) { "Security" } else { "Distribution" } } },
            @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Group.ReadWrite.All", "Directory.Read.All", "Policy.Read.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$caGroups = @{}
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage |
    ForEach-Object { @($_.conditions.users.includeGroups) + @($_.conditions.users.excludeGroups) } | Where-Object { $_ } |
    ForEach-Object { $caGroups[$_] = $true }
$backupRoot = if ($Identity) { [IO.Path]::GetTempPath() } else { $Path }
$backupFolder = New-Item -ItemType Directory -Path (Join-Path $backupRoot "deleted_groups_backup_$(Get-Date -Format yyyy-MM-dd)") -Force -WhatIf:$false

$results = Get-Candidates | Select-Removable | Select-Object -First $MaxRemovals | Remove-Group
$results | Format-Table displayName, Type, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_groups_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file and backups in $backupFolder"
}
