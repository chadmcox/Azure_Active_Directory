<#PSScriptInfo
.VERSION 2026.10
.GUID e427b52f-3bad-45c3-8cfd-9873a1b6ac75
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
Cleans up stale Conditional Access objects: removes references to deleted users, groups, roles, apps and named locations from policies, and deletes named locations no policy uses. Works from a reviewed Get-StaleCAObjects.ps1 report or finds them live. Never deletes or turns off a policy. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Update conditionalAccessPolicy - https://learn.microsoft.com/en-us/graph/api/conditionalaccesspolicy-update?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes deleted-object references from Conditional Access policies and deletes unused named locations.
.DESCRIPTION
    Every object is checked again before anything changes. A reference is not removed when it is the
    only entry in an include list, because an empty include list would change who the policy applies to;
    those are reported as "Skipped - review policy".
.PARAMETER CsvPath
    A reviewed Get-StaleCAObjects.ps1 report. Without it, stale objects are found live.
.PARAMETER MaxRemovals
    Stop after this many changes, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleCAObjects.ps1 -Environment Global -CsvPath .\entra_stale_conditional_access_objects.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$MaxRemovals = 25,
    [switch]$Identity,
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

$conditions = @(
    @("users", "includeUsers", "directoryObject"), @("users", "excludeUsers", "directoryObject"),
    @("users", "includeGroups", "directoryObject"), @("users", "excludeGroups", "directoryObject"),
    @("users", "includeRoles", "role"), @("users", "excludeRoles", "role"),
    @("applications", "includeApplications", "app"), @("applications", "excludeApplications", "app"),
    @("locations", "includeLocations", "location"), @("locations", "excludeLocations", "location")
)

function Test-Exists {
    param([string]$Id, [string]$Kind)
    switch ($Kind) {
        "directoryObject" { [bool]$(try { Invoke-MgGraphRequest -Uri "$script:Graph/directoryObjects/$($Id)?`$select=id" -OutputType PSObject -ErrorAction Stop } catch { $null }) }
        "role" { [bool]$(try { Invoke-MgGraphRequest -Uri "$script:Graph/roleManagement/directory/roleDefinitions/$Id" -OutputType PSObject -ErrorAction Stop } catch { $null }) }
        "app" { [bool]("$script:Graph/servicePrincipals?`$filter=appId eq '$Id'&`$select=id" | Get-GraphPage | Select-Object -First 1) }
        "location" { $locations.ContainsKey($Id) }
    }
}

function Get-Fixes {
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $p = $Policy
        foreach ($c in $conditions) {
            $current = @($p.conditions.($c[0]).($c[1]) | Where-Object { $_ })
            $dead = @($current | Where-Object { $_ -match "^[0-9a-fA-F-]{36}$" -and -not (Test-Exists -Id $_ -Kind $c[2]) })
            if ($wanted) { $dead = @($dead | Where-Object { $wanted.ContainsKey("$($p.id)|$($c[0]).$($c[1])|$_") }) }
            if (-not $dead) { continue }
            $remaining = @($current | Where-Object { $_ -notin $dead })
            $p | Select-Object @{ n = "Kind"; e = { "Reference" } }, @{ n = "Policy"; e = { $p.displayName } }, @{ n = "PolicyId"; e = { $p.id } },
                @{ n = "Section"; e = { $c[0] } }, @{ n = "Condition"; e = { $c[1] } },
                @{ n = "Removed"; e = { $dead -join ";" } }, @{ n = "Remaining"; e = { , $remaining } },
                @{ n = "Blocked"; e = { $c[1] -like "include*" -and -not $remaining } }
        }
    }
}

function Invoke-Fix {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Fix)
    process {
        $action = if ($Fix.Kind -eq "Reference" -and $Fix.Blocked) { "Skipped - review policy" }
            elseif ($Fix.Kind -eq "Reference" -and $PSCmdlet.ShouldProcess($Fix.Policy, "Remove $($Fix.Removed) from $($Fix.Section).$($Fix.Condition)")) {
                $body = @{ conditions = @{ $Fix.Section = @{ $Fix.Condition = @($Fix.Remaining) } } } | ConvertTo-Json -Depth 5
                Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/policies/$($Fix.PolicyId)" -Method PATCH -Body $body -ContentType "application/json"
                "Removed"
            } elseif ($Fix.Kind -eq "NamedLocation" -and $PSCmdlet.ShouldProcess($Fix.Policy, "Delete unused named location")) {
                Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/namedLocations/$($Fix.PolicyId)" -Method DELETE
                "Deleted"
            } else { "WhatIf" }
        $Fix | Select-Object Kind, Policy, PolicyId, Section, Condition, Removed, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.Read.All", "Application.Read.All", "RoleManagement.Read.Directory" -Identity:$Identity

$wanted = if ($CsvPath) {
    Import-Csv $CsvPath | Group-Object { if ($_.Finding -eq "UnusedNamedLocation") { "location|$($_.ObjectId)" } else { "$($_.PolicyId)|$($_.Condition)|$($_.ObjectId)" } } -AsHashTable -AsString
} else { $null }
$policies = @("$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage)
$locations = @("$script:Graph/identity/conditionalAccess/namedLocations" | Get-GraphPage) | Group-Object id -AsHashTable -AsString
if (-not $locations) { $locations = @{} }
$usedLocations = @($policies | ForEach-Object { @($_.conditions.locations.includeLocations) + @($_.conditions.locations.excludeLocations) } | Where-Object { $_ })

$results = @(
    $policies | Get-Fixes
    $locations.Values | ForEach-Object { $_ } | Where-Object { $_.id -notin $usedLocations -and (-not $wanted -or $wanted.ContainsKey("location|$($_.id)")) } |
        Select-Object @{ n = "Kind"; e = { "NamedLocation" } }, @{ n = "Policy"; e = { $_.displayName } }, @{ n = "PolicyId"; e = { $_.id } },
            @{ n = "Section"; e = { $null } }, @{ n = "Condition"; e = { $null } }, @{ n = "Removed"; e = { $_.displayName } }, @{ n = "Remaining"; e = { $null } }, @{ n = "Blocked"; e = { $false } }
) | Select-Object -First $MaxRemovals | Invoke-Fix
$results | Format-Table Kind, Policy, Condition, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_conditional_access_objects_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
