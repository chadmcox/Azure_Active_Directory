<#PSScriptInfo
.VERSION 2026.10
.GUID 3a5e1aff-0058-4a80-8dc6-3976fa54d6a8
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
Lists everyone excluded from each Conditional Access policy, expanding excluded groups (including nested groups) and roles down to the actual users, so exclusions can be reviewed.
url: Use access reviews to manage users excluded from Conditional Access policies - https://learn.microsoft.com/en-us/entra/id-governance/conditional-access-exclusion
#>
<#
.SYNOPSIS
    Exports every user, group and role excluded from Conditional Access policies.
.DESCRIPTION
    Replaces exportConditionalAccessExclusions and createConditionalAccessPolicyexclusionstats.
.PARAMETER IncludeDisabled
    Include disabled policies. By default only enabled and report-only policies are read.
.EXAMPLE
    .\Get-CAExclusions.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$IncludeDisabled,
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

function Format-Member {
    param([Parameter(ValueFromPipeline)]$Member, $Policy, [string]$Via, [string]$ViaName)
    process {
        $Member | Select-Object @{ n = "Policy"; e = { $Policy.displayName } },
            @{ n = "State"; e = { $Policy.state } },
            @{ n = "ExcludedVia"; e = { $Via } },
            @{ n = "ViaName"; e = { $ViaName } },
            @{ n = "MemberType"; e = { ($_.'@odata.type' -split "\.")[-1] } },
            @{ n = "MemberId"; e = { $_.id } },
            @{ n = "DisplayName"; e = { $_.displayName } },
            @{ n = "UserPrincipalName"; e = { $_.userPrincipalName } }
    }
}

function Get-Exclusions {
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $users = $Policy.conditions.users
        $users.excludeUsers | Where-Object { $_ -ne "GuestsOrExternalUsers" } | ForEach-Object {
            $found = try { Invoke-MgGraphRequest -Uri "$script:Graph/directoryObjects/$_" -OutputType PSObject -ErrorAction Stop } catch { $_ | Select-Object @{ n = "id"; e = { $_ } }, @{ n = "displayName"; e = { "not found" } } }
            $found | Format-Member -Policy $Policy -Via "User" -ViaName "Direct"
        }
        $users.excludeGroups | ForEach-Object {
            $group = Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($_)?`$select=id,displayName" -OutputType PSObject
            "$script:Graph/groups/$($group.id)/transitiveMembers?`$select=id,displayName,userPrincipalName" | Get-GraphPage |
                Format-Member -Policy $Policy -Via "Group" -ViaName $group.displayName
        }
        $users.excludeRoles | ForEach-Object {
            $role = Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/roleDefinitions/$_" -OutputType PSObject
            "$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$_'&`$expand=principal" | Get-GraphPage |
                ForEach-Object { $_.principal } | Format-Member -Policy $Policy -Via "Role" -ViaName $role.displayName
        }
        if ($users.excludeGuestsOrExternalUsers -or $users.excludeUsers -contains "GuestsOrExternalUsers") {
            $Policy | Select-Object @{ n = "Policy"; e = { $_.displayName } }, @{ n = "State"; e = { $_.state } },
                @{ n = "ExcludedVia"; e = { "Guests" } }, @{ n = "ViaName"; e = { $users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes } },
                @{ n = "MemberType"; e = { "guests" } }, @{ n = "MemberId"; e = { $null } }, @{ n = "DisplayName"; e = { "GuestsOrExternalUsers" } }, @{ n = "UserPrincipalName"; e = { $null } }
        }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Directory.Read.All", "RoleManagement.Read.Directory"

$file = Join-Path $Path "conditional_access_policy_exclusions.csv"
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage |
    Where-Object { $IncludeDisabled -or $_.state -ne "disabled" } |
    Get-Exclusions | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
