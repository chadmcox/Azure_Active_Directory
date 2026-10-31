<#PSScriptInfo
.VERSION 2026.10
.GUID 079606fc-f0bf-4f1c-b073-1dec63f759f0
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
Reports license use: each subscription's purchased and assigned counts, every user license assignment (direct or through a group) with any assignment error, and groups that have members in a license error state.
url: Group-based licensing - https://learn.microsoft.com/en-us/entra/identity/users/licensing-groups-assign
url: Identify and resolve license assignment problems - https://learn.microsoft.com/en-us/entra/identity/users/licensing-groups-resolve-problems
#>
<#
.SYNOPSIS
    Exports license counts, assignments and assignment errors.
.DESCRIPTION
    Writes three files: subscriptions (available versus assigned), user assignments (AssignedBy shows
    Direct or the group name; filter State = Error), and groups with license errors. The operations
    guide recommends group-based licensing, so a high Direct count is worth reviewing.
.EXAMPLE
    .\Get-LicenseReport.ps1 -Environment Global
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

function Get-Assignments {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $u = $User
        $u.licenseAssignmentStates | Where-Object { $_ } |
            Select-Object @{ n = "UserPrincipalName"; e = { $u.userPrincipalName } }, @{ n = "UserId"; e = { $u.id } }, @{ n = "AccountEnabled"; e = { $u.accountEnabled } },
                @{ n = "Sku"; e = { $skuNames[[string]$_.skuId] } }, skuId,
                @{ n = "AssignedBy"; e = { if ($_.assignedByGroup) { "Group: $($groupNames[[string]$_.assignedByGroup])" } else { "Direct" } } },
                state, error, @{ n = "DisabledPlans"; e = { @($_.disabledPlans).Count } }, lastUpdatedDateTime
    }
}

Connect-Cloud -Scopes "Organization.Read.All", "User.Read.All", "Group.Read.All"

$skus = @("$script:Graph/subscribedSkus" | Get-GraphPage)
$skuNames = @{}
$skus | ForEach-Object { $skuNames[[string]$_.skuId] = $_.skuPartNumber }
$licensedGroups = @("$script:Graph/groups?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=id,displayName,hasMembersWithLicenseErrors" | Get-GraphPage -Eventual)
$groupNames = @{}
$licensedGroups | ForEach-Object { $groupNames[[string]$_.id] = $_.displayName }

$skus | Select-Object skuPartNumber, skuId, capabilityStatus,
    @{ n = "Purchased"; e = { $_.prepaidUnits.enabled } }, @{ n = "Assigned"; e = { $_.consumedUnits } },
    @{ n = "Available"; e = { $_.prepaidUnits.enabled - $_.consumedUnits } },
    @{ n = "Suspended"; e = { $_.prepaidUnits.suspended } }, @{ n = "Warning"; e = { $_.prepaidUnits.warning } } |
    Export-Csv (Join-Path $Path "entra_license_subscriptions.csv") -NoTypeInformation

Write-Host "Reading user license assignments"
"$script:Graph/users?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=id,userPrincipalName,accountEnabled,licenseAssignmentStates" |
    Get-GraphPage -Eventual | Get-Assignments | Export-Csv (Join-Path $Path "entra_license_assignments.csv") -NoTypeInformation

$licensedGroups | Where-Object { $_.hasMembersWithLicenseErrors } | Select-Object id, displayName, hasMembersWithLicenseErrors |
    Export-Csv (Join-Path $Path "entra_license_group_errors.csv") -NoTypeInformation
Write-Host "Results: $Path\entra_license_*.csv"
