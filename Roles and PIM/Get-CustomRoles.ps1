<#PSScriptInfo
.VERSION 2026.10
.GUID 98b23290-1d3e-4e2a-ac86-7612b9929fea
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
Lists every custom directory role with its permissions, whether any permission is privileged, and who holds it (active and eligible), so custom roles that grant too much or are unused can be cleaned up.
url: Create and assign a custom role in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/custom-create
#>
<#
.SYNOPSIS
    Exports custom directory roles, their permissions and assignments.
.EXAMPLE
    .\Get-CustomRoles.ps1 -Environment Global
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

function Format-Role {
    param([Parameter(ValueFromPipeline)]$Role)
    process {
        $r = $Role
        $active = @("$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($r.id)'&`$expand=principal" | Get-GraphPage)
        $eligible = @(try { "$script:Graph/roleManagement/directory/roleEligibilitySchedules?`$filter=roleDefinitionId eq '$($r.id)'&`$expand=principal" | Get-GraphPage } catch { })
        $actions = @($r.rolePermissions.allowedResourceActions)
        $r | Select-Object displayName, id, description, isEnabled, isPrivileged,
            @{ n = "Permissions"; e = { $actions.Count } },
            @{ n = "PrivilegedPermissions"; e = { ($actions | Where-Object { $_ -match "credentials|owners|password|roleAssignments|authentication|policies/conditionalAccess" }) -join ";" } },
            @{ n = "ActiveAssignments"; e = { $active.Count } },
            @{ n = "EligibleAssignments"; e = { $eligible.Count } },
            @{ n = "Holders"; e = { (@($active) + @($eligible) | ForEach-Object { if ($_.principal.userPrincipalName) { $_.principal.userPrincipalName } else { $_.principal.displayName } } | Sort-Object -Unique) -join ";" } },
            @{ n = "AllPermissions"; e = { $actions -join ";" } }
    }
}

Connect-Cloud -Scopes "RoleManagement.Read.Directory", "Directory.Read.All"

$file = Join-Path $Path "entra_custom_roles.csv"
"$script:Graph/roleManagement/directory/roleDefinitions?`$filter=isBuiltIn eq false" | Get-GraphPage | Format-Role | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
