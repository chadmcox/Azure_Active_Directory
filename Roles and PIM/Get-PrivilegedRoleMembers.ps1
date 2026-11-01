<#PSScriptInfo
.VERSION 2026.10
.GUID 22b599b1-b00f-4bbd-948c-3749455ddce1
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
Reports everyone who holds a privileged directory role (active or eligible, including through groups and PIM for Groups) with account state, last sign-in and MFA registration.
url: List roleAssignmentScheduleInstances - https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentscheduleinstances?view=graph-rest-beta
url: List roleEligibilityScheduleInstances - https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleeligibilityscheduleinstances?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports members of privileged directory roles.
.DESCRIPTION
    Replaces export-HighlyPrivAccountsMFA and the -PrivilegedOnly switch that was on Get-RoleMembers.ps1.
    Privileged roles are the ones Microsoft marks as isPrivileged.
.EXAMPLE
    .\Get-PrivilegedRoleMembers.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
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
    param([ValidateSet("Active", "Eligible")][string]$State)
    $collection = if ($State -eq "Active") { "roleAssignmentScheduleInstances" } else { "roleEligibilityScheduleInstances" }
    try {
        "$script:Graph/roleManagement/directory/$($collection)?`$expand=principal" | Get-GraphPage |
            Select-Object *, @{ n = "AssignmentState"; e = { $State } }
    } catch {
        if ($State -eq "Active") {
            Write-Warning "PIM schedules are not available, using role assignments instead"
            "$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal" | Get-GraphPage |
                Select-Object *, @{ n = "AssignmentState"; e = { $State } }, @{ n = "assignmentType"; e = { "Assigned" } }
        } else {
            Write-Warning "Eligible assignments are not available (needs Microsoft Entra ID P2)"
        }
    }
}

function Expand-Principal {
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        $Assignment | Select-Object *, @{ n = "Via"; e = { "Direct" } }, @{ n = "Member"; e = { $_.principal } }
        if ($Assignment.principal.'@odata.type' -ne "#microsoft.graph.group") { return }
        $group = $Assignment.principal
        "$script:Graph/groups/$($group.id)/transitiveMembers" | Get-GraphPage | ForEach-Object {
            $member = $_
            $Assignment | Select-Object *, @{ n = "Via"; e = { "Group: $($group.displayName)" } }, @{ n = "Member"; e = { $member } }
        }
        try {
            "$script:Graph/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=groupId eq '$($group.id)'&`$expand=principal" | Get-GraphPage | ForEach-Object {
                $member = $_.principal
                $Assignment | Select-Object *, @{ n = "Via"; e = { "PIM group eligible: $($group.displayName)" } }, @{ n = "Member"; e = { $member } }
            }
        } catch { }
    }
}

function Get-UserDetail {
    param([string]$Id)
    if (-not $userCache.ContainsKey($Id)) {
        $user = Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Id)?`$select=id,accountEnabled,onPremisesSyncEnabled,signInActivity" -OutputType PSObject
        $registration = try { Invoke-MgGraphRequest -Uri "$script:Graph/reports/authenticationMethods/userRegistrationDetails/$Id" -OutputType PSObject -ErrorAction Stop } catch { $null }
        $userCache[$Id] = $user | Select-Object accountEnabled, onPremisesSyncEnabled,
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "IsMfaRegistered"; e = { $registration.isMfaRegistered } },
            @{ n = "MethodsRegistered"; e = { $registration.methodsRegistered -join ";" } }
    }
    $userCache[$Id]
}

function Format-RoleMember {
    param([Parameter(ValueFromPipeline)]$Row)
    process {
        $member = $Row.Member
        $role = $roles[$Row.roleDefinitionId]
        $type = ($member.'@odata.type' -split "\.")[-1]
        $user = if ($type -eq "user") { Get-UserDetail -Id $member.id }
        $Row | Select-Object @{ n = "RoleName"; e = { $role.displayName } },
            @{ n = "IsPrivileged"; e = { $role.isPrivileged } },
            @{ n = "Scope"; e = { $_.directoryScopeId } },
            AssignmentState,
            @{ n = "AssignmentType"; e = { $_.assignmentType } },
            @{ n = "Permanent"; e = { -not $_.endDateTime } },
            startDateTime, endDateTime, Via,
            @{ n = "PrincipalType"; e = { $type } },
            @{ n = "PrincipalId"; e = { $member.id } },
            @{ n = "DisplayName"; e = { $member.displayName } },
            @{ n = "UserPrincipalName"; e = { $member.userPrincipalName } },
            @{ n = "AppId"; e = { $member.appId } },
            @{ n = "AccountEnabled"; e = { if ($user) { $user.accountEnabled } else { $member.accountEnabled } } },
            @{ n = "OnPremisesSyncEnabled"; e = { $user.onPremisesSyncEnabled } },
            @{ n = "LastSignInDateTime"; e = { $user.LastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $user.LastNonInteractiveSignInDateTime } },
            @{ n = "IsMfaRegistered"; e = { $user.IsMfaRegistered } },
            @{ n = "MethodsRegistered"; e = { $user.MethodsRegistered } }
    }
}

Connect-Cloud -Scopes "RoleManagement.Read.Directory", "Directory.Read.All", "AuditLog.Read.All", "UserAuthenticationMethod.Read.All", "PrivilegedEligibilitySchedule.Read.AzureADGroup"

$roles = "$script:Graph/roleManagement/directory/roleDefinitions?`$select=id,displayName,isPrivileged,templateId" | Get-GraphPage | Group-Object id -AsHashTable -AsString
$userCache = @{}

Write-Host "Getting role assignments"
$rows = @(
    Get-Assignments -State Active
    Get-Assignments -State Eligible
) | Where-Object { $roles[$_.roleDefinitionId].isPrivileged } |
    Expand-Principal | Format-RoleMember

$file = Join-Path $Path "entra_privileged_role_members.csv"
$rows | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"

