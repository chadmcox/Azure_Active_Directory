<#PSScriptInfo
.VERSION 2026.10
.GUID aa5a9a02-5e63-4ddd-a8a6-54a4d0cb83d6
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
Finds stale Entra Agent ID objects and calls out each type separately: agent identities (service principals), agent users (user accounts tied to an agent identity), blueprint principals with no active agents, and blueprints that have no principal in this tenant.
url: Manage the lifecycle of agent identities - https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-identities-lifecycle
url: List agentIdentity objects - https://learn.microsoft.com/en-us/graph/api/agentidentity-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a stale Agent ID report.
.DESCRIPTION
    Status per object:
      Active      - signed in within the window
      New         - created within the window, no sign-in yet
      Stale       - last sign-in is older than the window
      NoActivity  - older than the window and never signed in
      Orphaned    - agent user whose parent agent identity is gone or disabled
      NoPrincipal - blueprint registered here with no principal (may be used in other tenants)
    Agent users sign in with their parent agent identity, so they take the parent's status.
    A blueprint principal is only stale when none of its agent identities are Active or New.
    Review the CSV, remove rows to keep, then pass it to Disable-StaleAgentIdentities.ps1 -CsvPath.
.PARAMETER Days
    Days without use. Default 90.
.EXAMPLE
    .\Get-StaleAgentIdentities.ps1 -Environment Global -Days 90
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

function Get-Status {
    param($Created, $LastSignIn)
    if ($LastSignIn -and [datetime]$LastSignIn -ge $cutoff) { return "Active" }
    if ($LastSignIn) { return "Stale" }
    if ($Created -and [datetime]$Created -ge $cutoff) { return "New" }
    "NoActivity"
}

function Get-SponsorCount {
    param([string]$Uri)
    @(try { $Uri | Get-GraphPage } catch { }).Count
}

function Format-Row {
    param([Parameter(ValueFromPipeline)]$Item)
    process {
        $last = $Item.LastSignIn
        $Item.Object | Select-Object @{ n = "ObjectType"; e = { $Item.ObjectType } }, id, appId, displayName, userPrincipalName, accountEnabled, createdDateTime,
            @{ n = "Parent"; e = { $Item.Parent } },
            @{ n = "Status"; e = { $Item.Status } },
            @{ n = "LastSignInDateTime"; e = { $last } },
            @{ n = "DaysSinceLastUse"; e = { if ($last) { [int]((Get-Date) - [datetime]$last).TotalDays } else { "Never" } } },
            @{ n = "ActiveChildren"; e = { $Item.ActiveChildren } },
            @{ n = "Sponsors"; e = { if ($Item.SponsorUri) { Get-SponsorCount -Uri $Item.SponsorUri } } },
            @{ n = "Recommendation"; e = {
                if ($Item.Status -eq "NoPrincipal") { "Review - may be used in other tenants" }
                elseif (-not $_.accountEnabled) { "Already disabled" }
                elseif ($Item.Status -in "Stale", "NoActivity", "Orphaned") { "Disable" }
                else { "Keep" } } }
    }
}

function Get-StaleIdentities {
    $agentIdentities | ForEach-Object {
        $last = $lastSignIns[[string]$_.appId].lastSignInActivity.lastSignInDateTime
        $_ | Select-Object @{ n = "Object"; e = { $_ } }, @{ n = "ObjectType"; e = { "AgentIdentity" } },
            @{ n = "Parent"; e = { $blueprintNames[[string]$_.agentIdentityBlueprintId].displayName } },
            @{ n = "Status"; e = { Get-Status -Created $_.createdDateTime -LastSignIn $last } },
            @{ n = "LastSignIn"; e = { $last } }, @{ n = "ActiveChildren"; e = { $null } },
            @{ n = "SponsorUri"; e = { "$script:Graph/servicePrincipals/$($_.id)/microsoft.graph.agentIdentity/sponsors?`$select=id" } }
    }
}

function Get-StaleAgentUsers {
    "$script:Graph/users/microsoft.graph.agentUser?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,identityParentId" | Get-GraphPage | ForEach-Object {
        $parent = $identities[[string]$_.identityParentId]
        $last = if ($parent) { $lastSignIns[[string]$parent.appId].lastSignInActivity.lastSignInDateTime }
        $status = if (-not $parent -or -not $parent.accountEnabled) { "Orphaned" } else { Get-Status -Created $_.createdDateTime -LastSignIn $last }
        $_ | Select-Object @{ n = "Object"; e = { $_ } }, @{ n = "ObjectType"; e = { "AgentUser" } },
            @{ n = "Parent"; e = { if ($parent) { $parent.displayName } else { "missing: $($_.identityParentId)" } } },
            @{ n = "Status"; e = { $status } }, @{ n = "LastSignIn"; e = { $last } }, @{ n = "ActiveChildren"; e = { $null } },
            @{ n = "SponsorUri"; e = { "$script:Graph/users/$($_.id)/sponsors?`$select=id" } }
    }
}

function Get-StaleBlueprintPrincipals {
    "$script:Graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal?`$select=id,appId,displayName,accountEnabled,createdDateTime" | Get-GraphPage | ForEach-Object {
        $principal = $_
        $last = $lastSignIns[[string]$principal.appId].lastSignInActivity.lastSignInDateTime
        $active = @($agentIdentities | Where-Object { $_.agentIdentityBlueprintId -eq $principal.appId -and $_.accountEnabled -and
            (Get-Status -Created $_.createdDateTime -LastSignIn $lastSignIns[[string]$_.appId].lastSignInActivity.lastSignInDateTime) -in "Active", "New" }).Count
        $own = Get-Status -Created $principal.createdDateTime -LastSignIn $last
        $principal | Select-Object @{ n = "Object"; e = { $_ } }, @{ n = "ObjectType"; e = { "BlueprintPrincipal" } },
            @{ n = "Parent"; e = { $blueprintNames[[string]$_.appId].displayName } },
            @{ n = "Status"; e = { if ($active -gt 0 -and $own -notin "Active", "New") { "Active" } else { $own } } },
            @{ n = "LastSignIn"; e = { $last } }, @{ n = "ActiveChildren"; e = { $active } }, @{ n = "SponsorUri"; e = { $null } }
    }
}

function Get-OrphanBlueprints {
    $principalAppIds = @("$script:Graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal?`$select=appId" | Get-GraphPage | Select-Object -ExpandProperty appId)
    $blueprints | Where-Object { $_.appId -notin $principalAppIds } |
        Select-Object @{ n = "Object"; e = { $_ | Select-Object *, @{ n = "accountEnabled"; e = { $null } } } }, @{ n = "ObjectType"; e = { "Blueprint" } },
            @{ n = "Parent"; e = { $null } }, @{ n = "Status"; e = { "NoPrincipal" } }, @{ n = "LastSignIn"; e = { $null } },
            @{ n = "ActiveChildren"; e = { 0 } }, @{ n = "SponsorUri"; e = { $null } }
}

Connect-Cloud -Scopes "Application.Read.All", "AgentIdentity.Read.All", "AgentIdentityBlueprint.Read.All", "User.Read.All", "AuditLog.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
Write-Host "Getting sign-in activity"
$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { Write-Warning "No sign-in activity found. Treat Disable recommendations as Review."; $lastSignIns = @{} }
$blueprints = @(try { "$script:Graph/applications/microsoft.graph.agentIdentityBlueprint?`$select=id,appId,displayName,createdDateTime" | Get-GraphPage } catch { Write-Warning "Blueprints: $($_.Exception.Message)" })
$blueprintNames = $blueprints | Group-Object appId -AsHashTable -AsString
if (-not $blueprintNames) { $blueprintNames = @{} }
Write-Host "Getting agent identities"
$agentIdentities = @("$script:Graph/servicePrincipals/microsoft.graph.agentIdentity?`$select=id,appId,displayName,accountEnabled,createdDateTime,agentIdentityBlueprintId" | Get-GraphPage)
$identities = $agentIdentities | Group-Object id -AsHashTable -AsString
if (-not $identities) { $identities = @{} }

$file = Join-Path $Path "entra_stale_agent_identities.csv"
@(
    Get-StaleIdentities
    Get-StaleAgentUsers
    Get-StaleBlueprintPrincipals
    Get-OrphanBlueprints
) | Where-Object { $_.Status -notin "Active", "New" } | Format-Row | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
