<#PSScriptInfo
.VERSION 2026.10
.GUID 04e35b43-7e03-4415-a5d6-5f1f46970427
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
Removes stale directory role assignments (held by disabled accounts, accounts with no sign-in, or eligible assignments never activated) through PIM admin remove requests, from a reviewed Get-StaleRoleAssignments.ps1 report or found live. Never touches Global Administrator, group assignments or the accounts you exclude. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Create roleAssignmentScheduleRequests - https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleassignmentschedulerequests?view=graph-rest-beta
url: Create roleEligibilityScheduleRequests - https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleeligibilityschedulerequests?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes stale role assignments.
.DESCRIPTION
    Every assignment is checked again before it is removed, so an account that signed in or activated
    after the report was made is skipped. Global Administrator assignments are never removed; review
    those by hand.
.PARAMETER CsvPath
    A reviewed Get-StaleRoleAssignments.ps1 report. Without it, stale assignments are found live.
.PARAMETER ExcludeAccount
    UPNs or object IDs to never touch, such as emergency access accounts.
.PARAMETER Days
    Days without use. Default 90.
.PARAMETER MaxRemovals
    Stop after this many assignments, as a safety limit. Default 10.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleRoleAssignments.ps1 -Environment Global -CsvPath .\entra_stale_role_assignments.csv -ExcludeAccount "<break glass UPN>" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [string[]]$ExcludeAccount = @(),
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

function Get-Assignments {
    $active = try {
        "$script:Graph/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal,roleDefinition" | Get-GraphPage |
            Where-Object { $_.assignmentType -ne "Activated" } | Select-Object *, @{ n = "State"; e = { "Active" } }, @{ n = "ViaPim"; e = { $true } }
    } catch {
        "$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal,roleDefinition" | Get-GraphPage |
            Select-Object *, @{ n = "State"; e = { "Active" } }, @{ n = "ViaPim"; e = { $false } }
    }
    $eligible = try {
        "$script:Graph/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal,roleDefinition" | Get-GraphPage |
            Select-Object *, @{ n = "State"; e = { "Eligible" } }, @{ n = "ViaPim"; e = { $true } }
    } catch { }
    @($active; $eligible)
}

function Test-Stale {
    param($Assignment)
    $principal = $Assignment.principal
    $act = switch -Wildcard ($principal.'@odata.type') {
        "*.user" {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($principal.id)?`$select=accountEnabled,signInActivity" -OutputType PSObject |
                Select-Object accountEnabled, @{ n = "LastSignIn"; e = { @($_.signInActivity.lastSignInDateTime, $_.signInActivity.lastNonInteractiveSignInDateTime) | Where-Object { $_ } | Sort-Object { [datetime]$_ } -Descending | Select-Object -First 1 } }
        }
        "*.servicePrincipal" { $principal | Select-Object accountEnabled, @{ n = "LastSignIn"; e = { $appSignIns[$_.appId].lastSignInActivity.lastSignInDateTime } } }
        default { return $false }
    }
    if (-not $act.accountEnabled) { return $true }
    if (-not $act.LastSignIn -or [datetime]$act.LastSignIn -lt $cutoff) { return $true }
    if ($Assignment.State -eq "Eligible" -and $Assignment.startDateTime -and [datetime]$Assignment.startDateTime -lt $cutoff) {
        $last = $activations["$($Assignment.principalId)|$($Assignment.roleDefinitionId)"]
        return (-not $last -or [datetime]$last -lt $cutoff)
    }
    $false
}

function Select-Removable {
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        $key = "$($Assignment.principalId)|$($Assignment.roleDefinitionId)|$($Assignment.State)"
        if ($wanted -and -not $wanted.ContainsKey($key)) { return }
        if ($Assignment.roleDefinition.displayName -eq "Global Administrator") { return }
        if ($Assignment.principal.'@odata.type' -like "*.group") { return }
        if ($Assignment.principalId -in $excludedIds -or $Assignment.principal.userPrincipalName -in $ExcludeAccount) { return }
        if (Test-Stale -Assignment $Assignment) { $Assignment }
    }
}

function Remove-Assignment {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        $who = if ($Assignment.principal.userPrincipalName) { $Assignment.principal.userPrincipalName } else { $Assignment.principal.displayName }
        $action = if (-not $PSCmdlet.ShouldProcess("$who - $($Assignment.roleDefinition.displayName) ($($Assignment.State))", "Remove role assignment")) { "WhatIf" }
            elseif (-not $Assignment.ViaPim) {
                Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/roleAssignments/$($Assignment.id)" -Method DELETE
                "Removed"
            } else {
                $collection = if ($Assignment.State -eq "Eligible") { "roleEligibilityScheduleRequests" } else { "roleAssignmentScheduleRequests" }
                $body = @{
                    action           = "adminRemove"
                    principalId      = $Assignment.principalId
                    roleDefinitionId = $Assignment.roleDefinitionId
                    directoryScopeId = $Assignment.directoryScopeId
                    justification    = "Stale role assignment removed by Remove-StaleRoleAssignments.ps1"
                } | ConvertTo-Json
                Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/$collection" -Method POST -Body $body -ContentType "application/json" | Out-Null
                "Removed"
            }
        $Assignment | Select-Object @{ n = "Principal"; e = { $who } }, @{ n = "Role"; e = { $_.roleDefinition.displayName } }, State, principalId, roleDefinitionId, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "RoleManagement.ReadWrite.Directory", "User.Read.All", "AuditLog.Read.All", "Application.Read.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$wanted = if ($CsvPath) { Import-Csv $CsvPath | Group-Object { "$($_.principalId)|$($_.roleDefinitionId)|$($_.State)" } -AsHashTable -AsString } else { $null }
$excludedIds = $ExcludeAccount | ForEach-Object { try { (Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_)?`$select=id" -OutputType PSObject -ErrorAction Stop).id } catch { $_ } }
$appSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $appSignIns) { $appSignIns = @{} }
$activations = @{}
try {
    "$script:Graph/roleManagement/directory/roleAssignmentScheduleRequests?`$filter=action eq 'selfActivate'" | Get-GraphPage |
        Sort-Object createdDateTime | ForEach-Object { $activations["$($_.principalId)|$($_.roleDefinitionId)"] = $_.createdDateTime }
} catch { }

$results = Get-Assignments | Select-Removable | Select-Object -First $MaxRemovals | Remove-Assignment
$results | Format-Table Principal, Role, State, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_role_assignments_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
