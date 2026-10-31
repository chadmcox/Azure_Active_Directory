<#PSScriptInfo
.VERSION 2026.10
.GUID de759438-1069-4e0f-b58c-740eb4b0e09e
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
Lists the apps and app roles every group is assigned to, to find broad groups (like All Users) that grant access to apps.
url: List appRoleAssignments granted to a group - https://learn.microsoft.com/en-us/graph/api/group-list-approleassignments?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports app role assignments for groups.
.DESCRIPTION
    Replaces AzureADModule\getAADAllUsersGroupAppRoleAssignment. Use -NameLike "All Users*" to match the old script.
.EXAMPLE
    .\Get-GroupAppRoleAssignments.ps1 -Environment Global -NameLike "All*"
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$NameLike = "*",
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
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        "$script:Graph/groups/$($Group.id)/appRoleAssignments" | Get-GraphPage |
            Select-Object @{ n = "Group"; e = { $Group.displayName } },
                @{ n = "GroupId"; e = { $Group.id } },
                @{ n = "GroupSynced"; e = { [bool]$Group.onPremisesSyncEnabled } },
                @{ n = "Dynamic"; e = { $Group.groupTypes -contains "DynamicMembership" } },
                resourceDisplayName, resourceId, appRoleId, createdDateTime
    }
}

Connect-Cloud -Scopes "Group.Read.All", "Application.Read.All"

$file = Join-Path $Path "entra_group_app_role_assignments.csv"
"$script:Graph/groups?`$select=id,displayName,groupTypes,onPremisesSyncEnabled" | Get-GraphPage |
    Where-Object { $_.displayName -like $NameLike } |
    Get-Assignments | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
