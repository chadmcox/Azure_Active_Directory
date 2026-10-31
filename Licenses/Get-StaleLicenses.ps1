<#PSScriptInfo
.VERSION 2026.10
.GUID 81313608-4cc9-4dcb-a484-149a6bd92c58
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
Finds licenses that are wasted: licenses assigned to disabled accounts and to accounts that have not signed in for a set number of days, and says whether each one is assigned directly or through a group.
url: Group-based licensing - https://learn.microsoft.com/en-us/entra/identity/users/licensing-groups-assign
#>
<#
.SYNOPSIS
    Creates a stale license report.
.DESCRIPTION
    Direct assignments can be removed with Remove-StaleLicenses.ps1. Licenses that come from a group
    must be removed by taking the user out of the group, so they are marked "Remove from group".
    Agent users are included, because they can hold licenses too.
.PARAMETER Days
    Days without a sign-in. Default 90.
.EXAMPLE
    .\Get-StaleLicenses.ps1 -Environment Global -Days 90
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 90,
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

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $u = $User
        $last = @($u.signInActivity.lastSignInDateTime, $u.signInActivity.lastNonInteractiveSignInDateTime) | Where-Object { $_ } |
            ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1
        $reason = if (-not $u.accountEnabled) { "AccountDisabled" }
            elseif ((-not $u.createdDateTime -or [datetime]$u.createdDateTime -lt $cutoff) -and (-not $last -or $last -lt $cutoff)) { "NoSignIn" }
        if (-not $reason) { return }
        $u.licenseAssignmentStates | Where-Object { $_ -and $_.state -eq "Active" } |
            Select-Object @{ n = "UserPrincipalName"; e = { $u.userPrincipalName } }, @{ n = "UserId"; e = { $u.id } },
                @{ n = "UserType"; e = { if ($u.identityParentId) { "AgentUser" } else { $u.userType } } },
                @{ n = "Sku"; e = { $skuNames[[string]$_.skuId] } }, skuId,
                @{ n = "AssignedBy"; e = { if ($_.assignedByGroup) { $_.assignedByGroup } else { "Direct" } } },
                @{ n = "StaleReason"; e = { $reason } },
                @{ n = "LastSignIn"; e = { $last } },
                @{ n = "Remediation"; e = { if ($_.assignedByGroup) { "Remove from group" } else { "Remove-StaleLicenses.ps1" } } }
    }
}

Connect-Cloud -Scopes "Organization.Read.All", "User.Read.All", "AuditLog.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
$skuNames = @{}
"$script:Graph/subscribedSkus" | Get-GraphPage | ForEach-Object { $skuNames[[string]$_.skuId] = $_.skuPartNumber }
$file = Join-Path $Path "entra_stale_licenses.csv"
Write-Host "Reading licensed users"
"$script:Graph/users?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=id,userPrincipalName,userType,accountEnabled,createdDateTime,identityParentId,licenseAssignmentStates,signInActivity" |
    Get-GraphPage -Eventual | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
