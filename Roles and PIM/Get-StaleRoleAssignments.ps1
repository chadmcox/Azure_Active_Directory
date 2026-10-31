<#PSScriptInfo
.VERSION 2026.10
.GUID 964a31d5-3f95-4096-9dbc-eb0792dbde23
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
Finds stale directory role assignments: active or eligible assignments held by disabled accounts, by users or apps that have not signed in for a set number of days, and eligible assignments that were never activated in that time.
url: Best practices for Microsoft Entra roles - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices
url: List roleAssignmentScheduleRequests - https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a stale role assignment report.
.DESCRIPTION
    StaleReason per assignment:
      AccountDisabled - the user or app is disabled
      NoSignIn        - no sign-in (user) or no sign-in activity (app) within the window
      NeverActivated  - eligible for longer than the window and not activated within it
    Assignments to groups are listed as "Review group members". Activated (temporary) PIM
    assignments are left out because they expire on their own.
    Review the CSV, remove rows to keep, then pass it to Remove-StaleRoleAssignments.ps1 -CsvPath.
.PARAMETER Days
    Days without use. Default 90.
.EXAMPLE
    .\Get-StaleRoleAssignments.ps1 -Environment Global -Days 90
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

function Get-Assignments {
    $active = try {
        "$script:Graph/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal,roleDefinition" | Get-GraphPage |
            Where-Object { $_.assignmentType -ne "Activated" } | Select-Object *, @{ n = "State"; e = { "Active" } }
    } catch {
        "$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal,roleDefinition" | Get-GraphPage | Select-Object *, @{ n = "State"; e = { "Active" } }
    }
    $eligible = try {
        "$script:Graph/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal,roleDefinition" | Get-GraphPage | Select-Object *, @{ n = "State"; e = { "Eligible" } }
    } catch { Write-Warning "Eligible assignments are not available (needs Microsoft Entra ID P2)" }
    @($active; $eligible)
}

function Get-PrincipalActivity {
    param($Principal)
    if (-not $activity.ContainsKey($Principal.id)) {
        $activity[$Principal.id] = switch -Wildcard ($Principal.'@odata.type') {
            "*.user" {
                Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Principal.id)?`$select=accountEnabled,signInActivity" -OutputType PSObject |
                    Select-Object accountEnabled, @{ n = "LastSignIn"; e = { @($_.signInActivity.lastSignInDateTime, $_.signInActivity.lastNonInteractiveSignInDateTime) | Where-Object { $_ } | Sort-Object { [datetime]$_ } -Descending | Select-Object -First 1 } }
            }
            "*.servicePrincipal" {
                $Principal | Select-Object accountEnabled, @{ n = "LastSignIn"; e = { $appSignIns[$_.appId].lastSignInActivity.lastSignInDateTime } }
            }
            default { $null }
        }
    }
    $activity[$Principal.id]
}

function Get-StaleReason {
    param($Assignment, $Activity)
    if (-not $Activity) { return }
    if (-not $Activity.accountEnabled) { return "AccountDisabled" }
    if (-not $Activity.LastSignIn -or [datetime]$Activity.LastSignIn -lt $cutoff) { return "NoSignIn" }
    if ($Assignment.State -eq "Eligible" -and $Assignment.startDateTime -and [datetime]$Assignment.startDateTime -lt $cutoff) {
        $last = $activations["$($Assignment.principalId)|$($Assignment.roleDefinitionId)"]
        if (-not $last -or [datetime]$last -lt $cutoff) { return "NeverActivated" }
    }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        $principal = $Assignment.principal
        $type = ($principal.'@odata.type' -split "\.")[-1]
        $act = Get-PrincipalActivity -Principal $principal
        $reason = if ($type -eq "group") { "Review group members" } else { Get-StaleReason -Assignment $Assignment -Activity $act }
        if (-not $reason) { return }
        $Assignment | Select-Object @{ n = "RoleName"; e = { $_.roleDefinition.displayName } },
            @{ n = "IsPrivileged"; e = { $_.roleDefinition.isPrivileged } },
            State, assignmentType,
            @{ n = "Permanent"; e = { -not $_.endDateTime } },
            principalId, roleDefinitionId, directoryScopeId,
            @{ n = "PrincipalType"; e = { $type } },
            @{ n = "DisplayName"; e = { $principal.displayName } },
            @{ n = "UserPrincipalName"; e = { $principal.userPrincipalName } },
            @{ n = "AccountEnabled"; e = { $act.accountEnabled } },
            @{ n = "LastSignIn"; e = { $act.LastSignIn } },
            @{ n = "LastActivation"; e = { $activations["$($_.principalId)|$($_.roleDefinitionId)"] } },
            @{ n = "StaleReason"; e = { $reason } },
            @{ n = "Remediation"; e = { if ($reason -eq "Review group members") { "Review group members" } elseif ($_.roleDefinition.displayName -eq "Global Administrator") { "Review by hand" } else { "Remove-StaleRoleAssignments.ps1" } } }
    }
}

Connect-Cloud -Scopes "RoleManagement.Read.Directory", "User.Read.All", "AuditLog.Read.All", "Application.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
$activity = @{}
$appSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $appSignIns) { $appSignIns = @{} }
Write-Host "Getting PIM activation history"
$activations = @{}
try {
    "$script:Graph/roleManagement/directory/roleAssignmentScheduleRequests?`$filter=action eq 'selfActivate'" | Get-GraphPage |
        Sort-Object createdDateTime | ForEach-Object { $activations["$($_.principalId)|$($_.roleDefinitionId)"] = $_.createdDateTime }
} catch { Write-Warning "PIM activation history is not available" }

$file = Join-Path $Path "entra_stale_role_assignments.csv"
Write-Host "Getting role assignments"
Get-Assignments | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
