<#PSScriptInfo
.VERSION 2026.10
.GUID c4ffb4d1-e076-494e-be07-4303a6f9d7e1
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
Creates one exclusion group per Conditional Access policy inside a restricted administrative unit and adds each group to its policy's exclusions, so exclusions are managed through groups instead of the policies.
url: Restricted management administrative units - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/admin-units-restricted-management
#>
<#
.SYNOPSIS
    Creates and links an exclusion group for every Conditional Access policy.
.DESCRIPTION
    Replaces add-ExclusionGroupALLCAP. Policies that already exclude a group with the same name are skipped.
.PARAMETER GroupPrefix
    Prefix for the group names. Default GRP.CAP.Exclude.
.EXAMPLE
    .\Add-ExclusionGroups.ps1 -Environment Global -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$GroupPrefix = "GRP.CAP.Exclude",
    [string]$AdminUnitName = "AU.CAP.Exclusion - Conditional Access Policy Exclusion Groups"
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

function Get-AdminUnit {
    $existing = "$script:Graph/administrativeUnits?`$filter=displayName eq '$AdminUnitName'" | Get-GraphPage | Select-Object -First 1
    if ($existing -or -not $PSCmdlet.ShouldProcess($AdminUnitName, "Create administrative unit")) { return $existing }
    $body = @{ displayName = $AdminUnitName; description = "Conditional Access policy exclusion groups"; visibility = "HiddenMembership"; isMemberManagementRestricted = $true } | ConvertTo-Json
    Invoke-MgGraphRequest -Uri "$script:Graph/administrativeUnits" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject
}

function Add-ExclusionGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $name = "$GroupPrefix - $($Policy.displayName)"
        $existing = "$script:Graph/groups?`$filter=displayName eq '$($name -replace "'", "''")'&`$select=id" | Get-GraphPage | Select-Object -First 1
        if ($existing -and $existing.id -in $Policy.conditions.users.excludeGroups) { Write-Output "OK      $($Policy.displayName)"; return }
        if (-not $PSCmdlet.ShouldProcess($Policy.displayName, "Create and exclude group $name")) { return }
        $group = if ($existing) { $existing } else {
            $body = @{
                "@odata.type"   = "#microsoft.graph.group"
                displayName     = $name
                description     = "Group to exclude from Conditional Access policy: $($Policy.displayName)"
                mailEnabled     = $false
                mailNickname    = "capExclude$(Get-Random -Maximum 100000)"
                securityEnabled = $true
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Uri "$script:Graph/administrativeUnits/$($adminUnit.id)/members" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject
        }
        $patch = @{ conditions = @{ users = @{ excludeGroups = @(@($Policy.conditions.users.excludeGroups) + $group.id | Where-Object { $_ }) } } } | ConvertTo-Json -Depth 5
        Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/policies/$($Policy.id)" -Method PATCH -Body $patch -ContentType "application/json"
        Write-Output "Updated $($Policy.displayName)"
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Group.ReadWrite.All", "AdministrativeUnit.ReadWrite.All"

$adminUnit = Get-AdminUnit
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage | Add-ExclusionGroup
