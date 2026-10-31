<#PSScriptInfo
.VERSION 2026.10
.GUID 79930526-3a4a-47f7-9e2e-99c6eed113d6
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
Exports the security groups every member user, guest and group belongs to, including nested membership, as three CSV files.
url: List transitiveMemberOf - https://learn.microsoft.com/en-us/graph/api/user-list-transitivememberof?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports transitive security group membership for users, guests and groups.
.DESCRIPTION
    Replaces export-groupsecuritymembership and Backup\export-GroupMemberShips.
.EXAMPLE
    .\Export-GroupMemberships.ps1 -Environment Global
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

function Get-SecurityGroupMembership {
    param([Parameter(ValueFromPipeline)]$Object, [string]$Collection)
    process {
        $member = $Object
        "$script:Graph/$Collection/$($member.id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,securityEnabled,onPremisesSyncEnabled" | Get-GraphPage |
            Where-Object { $_.securityEnabled } |
            Select-Object @{ n = "MemberId"; e = { $member.id } },
                @{ n = "Member"; e = { if ($member.userPrincipalName) { $member.userPrincipalName } else { $member.displayName } } },
                @{ n = "GroupId"; e = { $_.id } },
                @{ n = "Group"; e = { $_.displayName } },
                @{ n = "GroupSynced"; e = { [bool]$_.onPremisesSyncEnabled } }
    }
}

Connect-Cloud -Scopes "Group.Read.All", "User.Read.All", "Directory.Read.All"

Write-Host "Exporting member users"
"$script:Graph/users?`$filter=userType eq 'Member' and accountEnabled eq true&`$select=id,userPrincipalName" | Get-GraphPage |
    Get-SecurityGroupMembership -Collection users | Export-Csv (Join-Path $Path "group_membership_users.csv") -NoTypeInformation
Write-Host "Exporting guests"
"$script:Graph/users?`$filter=userType eq 'Guest' and accountEnabled eq true&`$select=id,userPrincipalName" | Get-GraphPage |
    Get-SecurityGroupMembership -Collection users | Export-Csv (Join-Path $Path "group_membership_guests.csv") -NoTypeInformation
Write-Host "Exporting groups"
"$script:Graph/groups?`$select=id,displayName" | Get-GraphPage |
    Get-SecurityGroupMembership -Collection groups | Export-Csv (Join-Path $Path "group_membership_groups.csv") -NoTypeInformation
Write-Host "Results: $Path\group_membership_*.csv"
