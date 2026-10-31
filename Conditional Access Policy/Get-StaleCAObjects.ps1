<#PSScriptInfo
.VERSION 2026.10
.GUID a7612cba-ac71-4f78-9fb0-e070bae58e2c
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
Finds stale objects in Conditional Access: users, groups, roles, apps and named locations that policies still point to but no longer exist, named locations no policy uses, and policies that have been turned off for a set number of days.
url: Plan a Conditional Access deployment - https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access
#>
<#
.SYNOPSIS
    Creates a stale Conditional Access object report.
.DESCRIPTION
    Finding per row:
      DeletedReference    - a policy includes or excludes something that was deleted
      UnusedNamedLocation - a named location no policy uses
      DisabledPolicy      - a policy turned off and not changed within the window (review by hand)
    Review the CSV, remove rows to keep, then pass it to Remove-StaleCAObjects.ps1 -CsvPath.
.PARAMETER Days
    Days a policy can stay off before it is reported. Default 90.
.EXAMPLE
    .\Get-StaleCAObjects.ps1 -Environment Global
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

# Condition path, object kind. Only object IDs are checked; keywords like All or GuestsOrExternalUsers are skipped.
$conditions = @(
    @("users", "includeUsers", "directoryObject"), @("users", "excludeUsers", "directoryObject"),
    @("users", "includeGroups", "directoryObject"), @("users", "excludeGroups", "directoryObject"),
    @("users", "includeRoles", "role"), @("users", "excludeRoles", "role"),
    @("applications", "includeApplications", "app"), @("applications", "excludeApplications", "app"),
    @("locations", "includeLocations", "location"), @("locations", "excludeLocations", "location")
)

function Test-Exists {
    param([string]$Id, [string]$Kind)
    $key = "$Kind|$Id"
    if (-not $exists.ContainsKey($key)) {
        $exists[$key] = switch ($Kind) {
            "directoryObject" { [bool]$(try { Invoke-MgGraphRequest -Uri "$script:Graph/directoryObjects/$($Id)?`$select=id" -OutputType PSObject -ErrorAction Stop } catch { $null }) }
            "role" { [bool]$(try { Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/roleDefinitions/$Id" -OutputType PSObject -ErrorAction Stop } catch { $null }) }
            "app" { [bool]("$script:Graph/servicePrincipals?`$filter=appId eq '$Id'&`$select=id" | Get-GraphPage | Select-Object -First 1) }
            "location" { $locations.ContainsKey($Id) }
        }
    }
    $exists[$key]
}

function Get-DeletedReferences {
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $p = $Policy
        foreach ($c in $conditions) {
            $p.conditions.($c[0]).($c[1]) | Where-Object { $_ -match "^[0-9a-fA-F-]{36}$" -and -not (Test-Exists -Id $_ -Kind $c[2]) } |
                Select-Object @{ n = "Finding"; e = { "DeletedReference" } }, @{ n = "Policy"; e = { $p.displayName } }, @{ n = "PolicyId"; e = { $p.id } },
                    @{ n = "State"; e = { $p.state } }, @{ n = "Condition"; e = { "$($c[0]).$($c[1])" } }, @{ n = "ObjectId"; e = { $_ } },
                    @{ n = "Remediation"; e = { "Remove-StaleCAObjects.ps1" } }
        }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Directory.Read.All", "Application.Read.All", "RoleManagement.Read.Directory"

$cutoff = (Get-Date).AddDays(-$Days)
$exists = @{}
$policies = @("$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage)
$locations = @("$script:Graph/identity/conditionalAccess/namedLocations" | Get-GraphPage) | Group-Object id -AsHashTable -AsString
if (-not $locations) { $locations = @{} }
$usedLocations = @($policies | ForEach-Object { @($_.conditions.locations.includeLocations) + @($_.conditions.locations.excludeLocations) } | Where-Object { $_ })

$file = Join-Path $Path "entra_stale_conditional_access_objects.csv"
@(
    $policies | Get-DeletedReferences
    $locations.Values | ForEach-Object { $_ } | Where-Object { $_.id -notin $usedLocations } |
        Select-Object @{ n = "Finding"; e = { "UnusedNamedLocation" } }, @{ n = "Policy"; e = { $null } }, @{ n = "PolicyId"; e = { $null } }, @{ n = "State"; e = { $null } },
            @{ n = "Condition"; e = { $_.displayName } }, @{ n = "ObjectId"; e = { $_.id } }, @{ n = "Remediation"; e = { "Remove-StaleCAObjects.ps1" } }
    $policies | Where-Object { $_.state -eq "disabled" -and $_.modifiedDateTime -and [datetime]$_.modifiedDateTime -lt $cutoff } |
        Select-Object @{ n = "Finding"; e = { "DisabledPolicy" } }, @{ n = "Policy"; e = { $_.displayName } }, @{ n = "PolicyId"; e = { $_.id } }, @{ n = "State"; e = { $_.state } },
            @{ n = "Condition"; e = { "off since $($_.modifiedDateTime)" } }, @{ n = "ObjectId"; e = { $null } }, @{ n = "Remediation"; e = { "Review by hand - delete or turn on" } }
) | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
