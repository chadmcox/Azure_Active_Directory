<#PSScriptInfo
.VERSION 2026.10
.GUID 90ae36ad-40ec-4987-b28b-f59d13d84521
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
Creates role-assignable security groups from a CSV of roleName and groupName pairs and gives each group a permanent active assignment to its directory role, so PIM for Groups can control who is in the role.
url: Create roleAssignmentScheduleRequests - https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleassignmentschedulerequests?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates role-assignable groups and assigns them to directory roles.
.DESCRIPTION
    Replaces PIM\addGrouptoRoleinPIM. The CSV needs two columns: roleName (the role's display name)
    and groupName (spaces are removed from the group name).
.EXAMPLE
    .\Add-GroupsToRoles.ps1 -Environment Global -CsvPath .\rolegroups.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string]$CsvPath
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

function Get-RoleGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)][string]$Name)
    process {
        $existing = "$script:Graph/groups?`$filter=displayName eq '$Name'&`$select=id,displayName" | Get-GraphPage | Select-Object -First 1
        if ($existing) { return $existing }
        if ($PSCmdlet.ShouldProcess($Name, "Create role-assignable group")) {
            $body = @{ displayName = $Name; mailNickname = $Name; mailEnabled = $false; securityEnabled = $true; isAssignableToRole = $true } | ConvertTo-Json
            Invoke-MgGraphRequest -Uri "$script:Graph/groups" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject
        }
    }
}

function Add-RoleAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Mapping)
    process {
        $role = $roles[$Mapping.roleName]
        $group = $groups[$Mapping.groupName]
        if (-not $role -or -not $group) { Write-Warning "Skipping $($Mapping.roleName) / $($Mapping.groupName): role or group not found"; return }
        if ($PSCmdlet.ShouldProcess("$($Mapping.groupName) -> $($Mapping.roleName)", "Assign role")) {
            $body = @{
                action           = "adminAssign"
                justification    = "Assign role to role-assignable group"
                roleDefinitionId = $role.id
                principalId      = $group.id
                directoryScopeId = "/"
                scheduleInfo     = @{ startDateTime = (Get-Date).ToUniversalTime().ToString("o"); expiration = @{ type = "noExpiration" } }
            } | ConvertTo-Json -Depth 5
            Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/roleAssignmentScheduleRequests" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject |
                Select-Object @{ n = "Role"; e = { $Mapping.roleName } }, @{ n = "Group"; e = { $Mapping.groupName } }, status
        }
    }
}

Connect-Cloud -Scopes "Group.ReadWrite.All", "RoleManagement.ReadWrite.Directory"

$mappings = Import-Csv $CsvPath | Select-Object roleName, @{ n = "groupName"; e = { $_.groupName -replace " ", "" } }
$roles = "$script:Graph/roleManagement/directory/roleDefinitions?`$select=id,displayName" | Get-GraphPage | Group-Object displayName -AsHashTable -AsString
$groups = @($mappings | Select-Object -ExpandProperty groupName -Unique | Get-RoleGroup) | Group-Object displayName -AsHashTable -AsString
if (-not $groups) { $groups = @{} }
Start-Sleep -Seconds 10
$mappings | Add-RoleAssignment
