<#PSScriptInfo
.VERSION 2026.10
.GUID 5246238a-c1ae-455b-82fe-74ae70f3a044
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
Lists every Intune role assignment with the groups and users that hold it and the permissions the role grants.
url: List roleAssignments (Intune) - https://learn.microsoft.com/en-us/graph/api/intune-rbac-deviceandappmanagementroleassignment-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports Intune role members and permissions.
.DESCRIPTION
    Replaces Intune\get-IntuneRoles (which showed results in Out-GridView).
.EXAMPLE
    .\Get-IntuneRoleAssignments.ps1 -Environment Global
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

function Expand-Assignment {
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        $a = $Assignment
        $definition = Invoke-MgGraphRequest -Uri "$script:Graph/deviceManagement/roleAssignments/$($a.id)?`$expand=roleDefinition" -OutputType PSObject
        $permissions = ($definition.roleDefinition.rolePermissions.resourceActions.allowedResourceActions) -join ";"
        $a.members | ForEach-Object {
            $group = Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($_)?`$select=id,displayName" -OutputType PSObject
            $group | Select-Object @{ n = "Role"; e = { $definition.roleDefinition.displayName } },
                @{ n = "Assignment"; e = { $a.displayName } },
                @{ n = "Group"; e = { $group.displayName } },
                @{ n = "Member"; e = { $group.displayName } },
                @{ n = "MemberType"; e = { "group" } },
                @{ n = "ScopeGroups"; e = { $a.resourceScopes -join ";" } },
                @{ n = "Permissions"; e = { $permissions } }
            "$script:Graph/groups/$($group.id)/transitiveMembers?`$select=id,displayName,userPrincipalName" | Get-GraphPage |
                Select-Object @{ n = "Role"; e = { $definition.roleDefinition.displayName } },
                    @{ n = "Assignment"; e = { $a.displayName } },
                    @{ n = "Group"; e = { $group.displayName } },
                    @{ n = "Member"; e = { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } } },
                    @{ n = "MemberType"; e = { ($_.'@odata.type' -split "\.")[-1] } },
                    @{ n = "ScopeGroups"; e = { $a.resourceScopes -join ";" } },
                    @{ n = "Permissions"; e = { $permissions } }
        }
    }
}

Connect-Cloud -Scopes "DeviceManagementRBAC.Read.All", "Group.Read.All"

$file = Join-Path $Path "intune_role_assignments.csv"
"$script:Graph/deviceManagement/roleAssignments" | Get-GraphPage | Expand-Assignment | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
