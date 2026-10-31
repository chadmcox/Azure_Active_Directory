<#PSScriptInfo
.VERSION 2026.10
.GUID 3ec2d81e-5ef3-4ff5-ad2c-da81b5a64270
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
Finds stale groups: cloud groups with no members and Microsoft 365 groups that have not been renewed for a set number of days, and flags groups that are still in use (Conditional Access, app assignments, licenses, roles) so they are not removed by mistake.
url: Configure the expiration policy for Microsoft 365 groups - https://learn.microsoft.com/en-us/entra/identity/users/groups-lifecycle
#>
<#
.SYNOPSIS
    Creates a stale group report.
.DESCRIPTION
    Review the CSV, remove any groups to keep, then pass it to Remove-StaleGroups.ps1 -CsvPath.
    Only empty, unused groups are removed by that script. Synced groups are reported with
    "Delete in Active Directory". Groups created inside the window are never stale.
.PARAMETER Days
    Minimum group age, and days since a Microsoft 365 group was last renewed. Default 180.
.EXAMPLE
    .\Get-StaleGroups.ps1 -Environment Global -Days 180
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 180,
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
    [int](Invoke-MgGraphRequest -Uri "$script:Graph/groups/$GroupId/transitiveMembers/`$count" -Headers @{ ConsistencyLevel = "eventual" })
}

function Get-UsedBy {
    param($Group)
    @(
        if ($caGroups.ContainsKey($Group.id)) { "ConditionalAccess" }
        if ($Group.isAssignableToRole) { "RoleAssignable" }
        if ($Group.assignedLicenses) { "Licenses" }
        if ("$script:Graph/groups/$($Group.id)/appRoleAssignments" | Get-GraphPage | Select-Object -First 1) { "AppAssignments" }
    ) -join ";"
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Group)
    process {
        if ($Group.createdDateTime -and [datetime]$Group.createdDateTime -ge $cutoff) { return }
        $members = Get-MemberCount -GroupId $Group.id
        $notRenewed = $Group.groupTypes -contains "Unified" -and $Group.renewedDateTime -and [datetime]$Group.renewedDateTime -lt $cutoff
        if ($members -gt 0 -and -not $notRenewed) { return }
        $usedBy = Get-UsedBy -Group $Group
        $Group | Select-Object id, displayName, mail, createdDateTime, renewedDateTime, onPremisesSyncEnabled, isAssignableToRole,
            @{ n = "Type"; e = { if ($_.groupTypes -contains "Unified") { "Microsoft 365" } elseif ($_.securityEnabled) { "Security" } else { "Distribution" } } },
            @{ n = "Membership"; e = { if ($_.groupTypes -contains "DynamicMembership") { "Dynamic" } else { "Assigned" } } },
            @{ n = "MemberCount"; e = { $members } },
            @{ n = "StaleReason"; e = { (@(if ($members -eq 0) { "Empty" }; if ($notRenewed) { "NotRenewed" })) -join ";" } },
            @{ n = "UsedBy"; e = { $usedBy } },
            @{ n = "Owners"; e = { ($_.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "Remediation"; e = {
                if ($usedBy) { "Keep - in use" }
                elseif ($_.onPremisesSyncEnabled) { "Delete in Active Directory" }
                elseif ($members -eq 0 -and $_.groupTypes -notcontains "DynamicMembership") { "Remove-StaleGroups.ps1" }
                else { "Ask owners or use a group expiration policy" } } }
    }
}

Connect-Cloud -Scopes "Group.Read.All", "Directory.Read.All", "Policy.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
Write-Host "Getting groups used by Conditional Access"
$caGroups = @{}
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage |
    ForEach-Object { @($_.conditions.users.includeGroups) + @($_.conditions.users.excludeGroups) } | Where-Object { $_ } |
    ForEach-Object { $caGroups[$_] = $true }

$file = Join-Path $Path "entra_stale_groups.csv"
Write-Host "Getting groups and counting members"
"$script:Graph/groups?`$select=id,displayName,mail,groupTypes,securityEnabled,createdDateTime,renewedDateTime,onPremisesSyncEnabled,isAssignableToRole,assignedLicenses&`$expand=owners(`$select=id,displayName,userPrincipalName)" |
    Get-GraphPage | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
