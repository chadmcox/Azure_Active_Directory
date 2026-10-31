<#PSScriptInfo
.VERSION 2026.10
.GUID a59f457f-e5cc-4b7f-852f-2ac91cd05f68
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
Disables stale Entra Agent ID objects: agent identities (service principals) and agent users (user accounts) with no sign-in for a set number of days, and blueprint principals with no active agents. Works from a reviewed Get-StaleAgentIdentities.ps1 report or finds them live. Never deletes and never touches blueprints. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Update agentIdentity - https://learn.microsoft.com/en-us/graph/api/agentidentity-update?view=graph-rest-beta
url: Manage the lifecycle of agent identities - https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-identities-lifecycle
#>
<#
.SYNOPSIS
    Disables stale agent identities, agent users and blueprint principals.
.DESCRIPTION
    Every object is checked again before it is disabled. Disabling can be undone by setting
    accountEnabled back to true. Deleting a blueprint deletes all its agent identities, so blueprints
    are only reported, never changed.
.PARAMETER CsvPath
    A reviewed Get-StaleAgentIdentities.ps1 report. Only rows with Recommendation "Disable" are used.
    Without it, stale objects are found live.
.PARAMETER ObjectType
    Which types to disable. Default all three.
.PARAMETER Days
    Days without use. Default 90.
.PARAMETER MaxRemovals
    Stop after this many objects, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Disable-StaleAgentIdentities.ps1 -Environment Global -CsvPath .\entra_stale_agent_identities.csv -WhatIf
.EXAMPLE
    .\Disable-StaleAgentIdentities.ps1 -Environment Global -ObjectType AgentUser -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [ValidateSet("AgentIdentity", "AgentUser", "BlueprintPrincipal")][string[]]$ObjectType = @("AgentIdentity", "AgentUser", "BlueprintPrincipal"),
    [int]$Days = 90,
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

function Get-Candidates {
    $wanted = if ($CsvPath) { Import-Csv $CsvPath | Where-Object { $_.Recommendation -eq "Disable" } | Group-Object id -AsHashTable -AsString } else { $null }
    @(
        if ("AgentIdentity" -in $ObjectType) { $agentIdentities | Select-Object *, @{ n = "ObjectType"; e = { "AgentIdentity" } } }
        if ("AgentUser" -in $ObjectType) {
            "$script:Graph/users/microsoft.graph.agentUser?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,identityParentId" | Get-GraphPage |
                Select-Object *, @{ n = "ObjectType"; e = { "AgentUser" } }
        }
        if ("BlueprintPrincipal" -in $ObjectType) {
            "$script:Graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal?`$select=id,appId,displayName,accountEnabled,createdDateTime" | Get-GraphPage |
                Select-Object *, @{ n = "ObjectType"; e = { "BlueprintPrincipal" } }
        }
    ) | Where-Object { $_.accountEnabled -and (-not $wanted -or $wanted.ContainsKey($_.id)) }
}

function Test-Used {
    param($Created, [string]$AppId)
    $last = $lastSignIns[[string]$AppId].lastSignInActivity.lastSignInDateTime
    ($last -and [datetime]$last -ge $cutoff) -or ($Created -and [datetime]$Created -ge $cutoff)
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Object)
    process {
        $stale = switch ($Object.ObjectType) {
            "AgentIdentity" { -not (Test-Used -Created $Object.createdDateTime -AppId $Object.appId) }
            "AgentUser" {
                $parent = $identities[[string]$Object.identityParentId]
                -not $parent -or -not $parent.accountEnabled -or (-not (Test-Used -Created $Object.createdDateTime -AppId $parent.appId) -and -not (Test-Used -Created $parent.createdDateTime -AppId $parent.appId))
            }
            "BlueprintPrincipal" {
                $activeChildren = $agentIdentities | Where-Object { $_.agentIdentityBlueprintId -eq $Object.appId -and $_.accountEnabled -and (Test-Used -Created $_.createdDateTime -AppId $_.appId) }
                -not $activeChildren -and -not (Test-Used -Created $Object.createdDateTime -AppId $Object.appId)
            }
        }
        if ($stale) { $Object }
    }
}

function Disable-Agent {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Object)
    process {
        $uri = switch ($Object.ObjectType) {
            "AgentIdentity" { "$script:Graph/servicePrincipals/$($Object.id)/microsoft.graph.agentIdentity" }
            "AgentUser" { "$script:Graph/users/$($Object.id)" }
            "BlueprintPrincipal" { "$script:Graph/servicePrincipals/$($Object.id)" }
        }
        $action = if ($PSCmdlet.ShouldProcess("$($Object.ObjectType) $($Object.displayName)", "Disable")) {
            Invoke-MgGraphRequest -Uri $uri -Method PATCH -Body (@{ accountEnabled = $false } | ConvertTo-Json) -ContentType "application/json"
            "Disabled"
        } else { "WhatIf" }
        $Object | Select-Object ObjectType, id, appId, displayName, userPrincipalName, createdDateTime, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "AgentIdentity.EnableDisable.All", "AgentIdentity.Read.All", "AgentIdentityBlueprintPrincipal.EnableDisable.All", "AgentIdUser.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { throw "Couldn't read service principal sign-in activity, so stale agents can't be told apart. Nothing was changed." }
$agentIdentities = @("$script:Graph/servicePrincipals/microsoft.graph.agentIdentity?`$select=id,appId,displayName,accountEnabled,createdDateTime,agentIdentityBlueprintId" | Get-GraphPage)
$identities = $agentIdentities | Group-Object id -AsHashTable -AsString
if (-not $identities) { $identities = @{} }

$results = Get-Candidates | Select-Stale | Select-Object -First $MaxRemovals | Disable-Agent
$results | Format-Table ObjectType, displayName, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_agent_identities_disabled.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
