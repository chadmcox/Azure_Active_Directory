<#PSScriptInfo
.VERSION 2026.10
.GUID 9d4a1e70-ad9a-4d8b-8448-0fd6508e8ed6
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
Backs up cloud-only security groups to JSON: assigned members, dynamic membership rules, owners and app role assignments, so a deleted or changed group can be rebuilt.
url: List group members - https://learn.microsoft.com/en-us/graph/api/group-list-members?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Backs up cloud security groups, members, dynamic rules and app role assignments.
.DESCRIPTION
    Replaces backup-CloudSecurityGroupMembers, backup-DynamicSecurityGroupMemberShipRules and
    backup-GroupsAppRoleAssignment.
.EXAMPLE
    .\Backup-CloudGroups.ps1 -Environment Global
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

function Add-GroupDetail {
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        $Group | Select-Object id, displayName, description, mailNickname, mailEnabled, securityEnabled, groupTypes, isAssignableToRole, membershipRule, membershipRuleProcessingState,
            @{ n = "owners"; e = { "$script:Graph/groups/$($_.id)/owners?`$select=id,displayName,userPrincipalName" | Get-GraphPage | Select-Object id, displayName, userPrincipalName } },
            @{ n = "members"; e = { if ($_.groupTypes -notcontains "DynamicMembership") { "$script:Graph/groups/$($_.id)/members?`$select=id,displayName,userPrincipalName" | Get-GraphPage | Select-Object id, displayName, userPrincipalName } } },
            @{ n = "appRoleAssignments"; e = { "$script:Graph/groups/$($_.id)/appRoleAssignments" | Get-GraphPage | Select-Object appRoleId, resourceId, resourceDisplayName } }
    }
}

Connect-Cloud -Scopes "Group.Read.All", "Directory.Read.All"

$file = Join-Path $Path "backup_cloud_security_groups_$(Get-Date -Format yyyy-MM-dd).json"
Write-Host "Backing up cloud security groups"
"$script:Graph/groups?`$filter=securityEnabled eq true&`$select=id,displayName,description,mailNickname,mailEnabled,securityEnabled,groupTypes,isAssignableToRole,membershipRule,membershipRuleProcessingState,onPremisesSyncEnabled" | Get-GraphPage |
    Where-Object { -not $_.onPremisesSyncEnabled -and $_.groupTypes -notcontains "Unified" } |
    Add-GroupDetail | ConvertTo-Json -Depth 6 | Out-File $file
Write-Host "Results: $file"
