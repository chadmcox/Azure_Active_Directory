<#PSScriptInfo
.VERSION 2026.10
.GUID 2e63c0cc-3df5-48b7-85ae-a05947d1b5f2
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
Reports every group with its type, member and owner counts, licenses, dynamic rule state and duplicate names, so empty, ownerless, duplicate and broken dynamic groups can be found in one file.
url: List groups - https://learn.microsoft.com/en-us/graph/api/group-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports a report of all groups.
.DESCRIPTION
    Replaces get-GroupMemberCount, get-EmptySecurityGroups, get-SyncedEmptySecurityGroups,
    get-OwnerlessSecurityGroups, get-OwnerlessUnifiedGroups, get-DynamicGroupProcessingStateNotOn,
    get-memberofdynamicgroups, find-DuplicateGroups, Backup\export-Groups and the AzureADModule scripts
    getAADGroupsMissingOwner, getMemberlessAADGroups, getMemberlessAADUnifiedGroups, getAADLicensedGroups
    and getAADUnifiedGroupsMissingLifecyclePolicies.
    Filter the CSV: MemberCount 0 = empty, OwnerCount 0 = ownerless, DuplicateNameCount > 1 = duplicates,
    DynamicRuleState not On = paused dynamic group, RuleUsesMemberOf = dynamic rule based on other groups.
.EXAMPLE
    .\Get-GroupReport.ps1 -Environment Global
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

function Get-MemberCount {
    param([string]$GroupId)
    Invoke-MgGraphRequest -Uri "$script:Graph/groups/$GroupId/transitiveMembers/`$count" -Headers @{ ConsistencyLevel = "eventual" }
}

function Get-LifecyclePolicy {
    param($Group)
    if ($Group.groupTypes -notcontains "Unified" -or -not $lifecyclePolicy) { return }
    # Only a "Selected" policy needs a per-group lookup; "All" covers every Microsoft 365 group.
    if ($lifecyclePolicy.managedGroupTypes -eq "All") { return $lifecyclePolicy.groupLifetimeInDays }
    ("$script:Graph/groups/$($Group.id)/groupLifecyclePolicies" | Get-GraphPage | Select-Object -First 1).groupLifetimeInDays
}

function Format-Group {
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        Write-Host "  $($Group.displayName)"
        $Group | Select-Object id, displayName,
            @{ n = "Type"; e = { if ($_.groupTypes -contains "Unified") { "Microsoft 365" } elseif ($_.securityEnabled -and $_.mailEnabled) { "Mail-enabled security" } elseif ($_.securityEnabled) { "Security" } else { "Distribution" } } },
            @{ n = "Membership"; e = { if ($_.groupTypes -contains "DynamicMembership") { "Dynamic" } else { "Assigned" } } },
            onPremisesSyncEnabled, onPremisesDomainName, onPremisesLastSyncDateTime, isAssignableToRole, mail, createdDateTime, expirationDateTime,
            @{ n = "MemberCount"; e = { Get-MemberCount -GroupId $_.id } },
            @{ n = "OwnerCount"; e = { @($_.owners).Count } },
            @{ n = "Owners"; e = { ($_.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "Licenses"; e = { @($_.assignedLicenses).Count } },
            @{ n = "LifecyclePolicyDays"; e = { Get-LifecyclePolicy -Group $_ } },
            @{ n = "DuplicateNameCount"; e = { $nameCounts[$_.displayName].Count } },
            @{ n = "DynamicRuleState"; e = { $_.membershipRuleProcessingState } },
            @{ n = "RuleUsesMemberOf"; e = { $_.membershipRule -match "memberOf" } },
            membershipRule
    }
}

Connect-Cloud -Scopes "Group.Read.All", "Directory.Read.All"

$lifecyclePolicy = "$script:Graph/groupLifecyclePolicies" | Get-GraphPage | Where-Object { $_.managedGroupTypes -ne "None" } | Select-Object -First 1
Write-Host "Getting groups"
$groups = "$script:Graph/groups?`$select=id,displayName,groupTypes,securityEnabled,mailEnabled,mail,onPremisesSyncEnabled,onPremisesDomainName,onPremisesLastSyncDateTime,isAssignableToRole,createdDateTime,expirationDateTime,assignedLicenses,membershipRule,membershipRuleProcessingState&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage
$nameCounts = $groups | Group-Object displayName -AsHashTable -AsString

$file = Join-Path $Path "entra_groups.csv"
Write-Host "Counting members"
$groups | Format-Group | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
