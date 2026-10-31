<#PSScriptInfo
.VERSION 2026.10
.GUID 02425da5-abb4-45a6-979d-3a36cba21a98
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
Exports what guests have access to and own: group memberships, app role assignments and owned objects, for review or as a backup before removing guests.
url: List memberOf - https://learn.microsoft.com/en-us/graph/api/user-list-memberof?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports guest group memberships, app role assignments and owned objects.
.DESCRIPTION
    Replaces backup-GuestGroupMembership, backup-GuestAppRoleAssignments and find-GuestOwnedObjects.
.EXAMPLE
    .\Get-GuestAccess.ps1 -Environment Global
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

function Get-Access {
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $g = $Guest
        "$script:Graph/users/$($g.id)/memberOf?`$select=id,displayName" | Get-GraphPage |
            Select-Object @{ n = "Guest"; e = { $g.userPrincipalName } }, @{ n = "GuestId"; e = { $g.id } },
                @{ n = "AccessType"; e = { "MemberOf " + ($_.'@odata.type' -split "\.")[-1] } }, @{ n = "TargetId"; e = { $_.id } }, @{ n = "Target"; e = { $_.displayName } }, @{ n = "AppRoleId"; e = { $null } }
        "$script:Graph/users/$($g.id)/appRoleAssignments" | Get-GraphPage |
            Select-Object @{ n = "Guest"; e = { $g.userPrincipalName } }, @{ n = "GuestId"; e = { $g.id } },
                @{ n = "AccessType"; e = { "AppRoleAssignment" } }, @{ n = "TargetId"; e = { $_.resourceId } }, @{ n = "Target"; e = { $_.resourceDisplayName } }, appRoleId
        "$script:Graph/users/$($g.id)/ownedObjects?`$select=id,displayName" | Get-GraphPage |
            Select-Object @{ n = "Guest"; e = { $g.userPrincipalName } }, @{ n = "GuestId"; e = { $g.id } },
                @{ n = "AccessType"; e = { "Owner of " + ($_.'@odata.type' -split "\.")[-1] } }, @{ n = "TargetId"; e = { $_.id } }, @{ n = "Target"; e = { $_.displayName } }, @{ n = "AppRoleId"; e = { $null } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "Directory.Read.All"

$file = Join-Path $Path "entra_guest_access.csv"
"$script:Graph/users?`$filter=userType eq 'Guest'&`$select=id,userPrincipalName" | Get-GraphPage |
    Get-Access | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
