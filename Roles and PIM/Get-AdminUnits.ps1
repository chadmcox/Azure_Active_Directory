<#PSScriptInfo
.VERSION 2026.10
.GUID 34c9d588-13c0-480f-856e-32fcef8137ab
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
Lists every administrative unit with its membership type, member count, whether management is restricted, and the admins whose roles are scoped to it.
url: Administrative units in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/administrative-units
#>
<#
.SYNOPSIS
    Exports administrative units, members and scoped role holders.
.EXAMPLE
    .\Get-AdminUnits.ps1 -Environment Global
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

function Format-Unit {
    param([Parameter(ValueFromPipeline)]$Unit)
    process {
        $u = $Unit
        $scoped = @("$script:Graph/administrativeUnits/$($u.id)/scopedRoleMembers" | Get-GraphPage)
        $u | Select-Object displayName, id, description, membershipType, membershipRule, isMemberManagementRestricted, visibility,
            @{ n = "Members"; e = { [int](Invoke-MgGraphRequest -Uri "$script:Graph/administrativeUnits/$($u.id)/members/`$count" -Headers @{ ConsistencyLevel = "eventual" }) } },
            @{ n = "ScopedAdmins"; e = { ($scoped | ForEach-Object { "$($roles[[string]$_.roleId]): $($_.roleMemberInfo.displayName)" }) -join ";" } }
    }
}

Connect-Cloud -Scopes "AdministrativeUnit.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All"

$roles = @{}
"$script:Graph/directoryRoles?`$select=id,displayName" | Get-GraphPage | ForEach-Object { $roles[[string]$_.id] = $_.displayName }
$file = Join-Path $Path "entra_admin_units.csv"
"$script:Graph/administrativeUnits" | Get-GraphPage | Format-Unit | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
