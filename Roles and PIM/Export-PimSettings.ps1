<#PSScriptInfo
.VERSION 2026.10
.GUID 39ad5865-1fc4-4e47-9ec4-7495e8779a1c
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
Exports the PIM settings (role management policy rules) for every directory role and every group onboarded to PIM for Groups, one JSON file per role or group plus a summary CSV.
url: List roleManagementPolicyAssignments - https://learn.microsoft.com/en-us/graph/api/policyroot-list-rolemanagementpolicyassignments?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Backs up PIM role and group settings.
.DESCRIPTION
    Replaces PIM\export-PIMSettings and the empty PIM\backup-PIMDirectoryRoleSettings.
.EXAMPLE
    .\Export-PimSettings.ps1 -Environment Global
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

function Export-Policy {
    param([Parameter(ValueFromPipeline)]$Assignment, [string]$Folder, [string]$Name)
    process {
        $safeName = ($Name -replace '[\\/:*?"<>|]', "_")
        $Assignment.policy | ConvertTo-Json -Depth 20 | Out-File (Join-Path $Folder "$safeName-$($Assignment.roleDefinitionId).json")
        $Assignment.policy.rules | Select-Object @{ n = "Target"; e = { $Name } },
            @{ n = "RoleDefinitionId"; e = { $Assignment.roleDefinitionId } },
            @{ n = "RuleId"; e = { $_.id } },
            @{ n = "Setting"; e = { $_ | Select-Object * -ExcludeProperty id, target | ConvertTo-Json -Depth 10 -Compress } }
    }
}

Connect-Cloud -Scopes "RoleManagementPolicy.Read.Directory", "RoleManagementPolicy.Read.AzureADGroup", "RoleManagement.Read.Directory", "PrivilegedAccess.Read.AzureADGroup"

$roleFolder = New-Item -ItemType Directory -Path (Join-Path $Path "PIM_Roles") -Force
$groupFolder = New-Item -ItemType Directory -Path (Join-Path $Path "PIM_Groups") -Force
$roles = "$script:Graph/roleManagement/directory/roleDefinitions?`$select=id,displayName" | Get-GraphPage | Group-Object id -AsHashTable -AsString

$summary = @(
    Write-Host "Exporting directory role settings"
    "$script:Graph/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'&`$expand=policy(`$expand=rules)" | Get-GraphPage |
        ForEach-Object { $_ | Export-Policy -Folder $roleFolder -Name $(if ($_.roleDefinitionId) { $roles[$_.roleDefinitionId].displayName } else { $_.id }) }

    Write-Host "Exporting PIM for Groups settings"
    "$script:Graph/identityGovernance/privilegedAccess/group/resources" | Get-GraphPage | ForEach-Object {
        $group = $_
        "$script:Graph/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$($group.id)' and scopeType eq 'Group'&`$expand=policy(`$expand=rules)" | Get-GraphPage |
            Export-Policy -Folder $groupFolder -Name $group.displayName
    }
)
$file = Join-Path $Path "entra_pim_settings.csv"
$summary | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file, $roleFolder, $groupFolder"
