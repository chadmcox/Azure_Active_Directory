<#PSScriptInfo
.VERSION 2026.10
.GUID db02097d-cb6f-4f57-9e62-d1500810763a
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
Inventories every Entra Agent ID object, separated by type: agent identity blueprints, blueprint principals, agent identities (service principals), agent users (user accounts) and Copilot Studio agent apps, with their parent, sponsors and last sign-in.
url: What is Microsoft Entra Agent ID - https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id
url: agentUser resource type - https://learn.microsoft.com/en-us/graph/api/resources/agentuser?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports all Agent ID objects.
.DESCRIPTION
    Replaces Agent 365\Get Agent Related Service Principals, Agent 365\Get agent related user identities
    and Applications\get-EntraCopilotServicePrincipals.
    ObjectType tells the types apart:
      Blueprint            - the agent identity blueprint (an application object, the template)
      BlueprintPrincipal   - the blueprint's service principal in this tenant
      AgentIdentity        - an agent's service principal identity (app-only and on-behalf-of access)
      AgentUser            - an agent's user account (mailbox, Teams, licenses), tied to one agent identity
      CopilotStudioApp     - a classic Copilot Studio agent app registration
    Agent users sign in with their parent agent identity's credentials, so their last sign-in comes from the parent.
.EXAMPLE
    .\Get-AgentIdentities.ps1 -Environment Global
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

function Get-Sponsors {
    param([string]$Uri)
    (@(try { $Uri | Get-GraphPage } catch { }) | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";"
}

function Format-Agent {
    param([Parameter(ValueFromPipeline)]$Agent, [string]$ObjectType)
    process {
        $parentAppId = switch ($ObjectType) {
            "AgentIdentity" { $Agent.agentIdentityBlueprintId }
            "AgentUser" { $identities[[string]$Agent.identityParentId].appId }
            default { $Agent.appId }
        }
        $Agent | Select-Object @{ n = "ObjectType"; e = { $ObjectType } }, id, appId, displayName, userPrincipalName, accountEnabled, createdDateTime,
            @{ n = "Parent"; e = {
                switch ($ObjectType) {
                    "AgentIdentity" { "Blueprint: $($blueprintNames[[string]$_.agentIdentityBlueprintId].displayName)" }
                    "AgentUser" { "Agent identity: $($identities[[string]$_.identityParentId].displayName)" }
                    "BlueprintPrincipal" { "Blueprint: $($blueprintNames[[string]$_.appId].displayName)" }
                } } },
            @{ n = "ParentId"; e = { if ($ObjectType -eq "AgentUser") { $_.identityParentId } elseif ($ObjectType -eq "AgentIdentity") { $_.agentIdentityBlueprintId } } },
            @{ n = "Sponsors"; e = {
                switch ($ObjectType) {
                    "AgentIdentity" { Get-Sponsors -Uri "$script:Graph/servicePrincipals/$($_.id)/microsoft.graph.agentIdentity/sponsors?`$select=id,displayName,userPrincipalName" }
                    "AgentUser" { Get-Sponsors -Uri "$script:Graph/users/$($_.id)/sponsors?`$select=id,displayName,userPrincipalName" }
                } } },
            @{ n = "LastSignInDateTime"; e = { $lastSignIns[[string]$parentAppId].lastSignInActivity.lastSignInDateTime } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "AgentIdentity.Read.All", "AgentIdentityBlueprint.Read.All", "User.Read.All", "AuditLog.Read.All"

$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { $lastSignIns = @{} }
$blueprints = @(try { "$script:Graph/applications/microsoft.graph.agentIdentityBlueprint?`$select=id,appId,displayName,createdDateTime" | Get-GraphPage } catch { Write-Warning "Blueprints: $($_.Exception.Message)" })
$blueprintNames = $blueprints | Group-Object appId -AsHashTable -AsString
if (-not $blueprintNames) { $blueprintNames = @{} }
$agentIdentities = @("$script:Graph/servicePrincipals/microsoft.graph.agentIdentity?`$select=id,appId,displayName,accountEnabled,createdDateTime,agentIdentityBlueprintId" | Get-GraphPage)
$identities = $agentIdentities | Group-Object id -AsHashTable -AsString
if (-not $identities) { $identities = @{} }

$file = Join-Path $Path "entra_agent_identities.csv"
@(
    $blueprints | Format-Agent -ObjectType "Blueprint"
    "$script:Graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal?`$select=id,appId,displayName,accountEnabled,createdDateTime" | Get-GraphPage | Format-Agent -ObjectType "BlueprintPrincipal"
    $agentIdentities | Format-Agent -ObjectType "AgentIdentity"
    "$script:Graph/users/microsoft.graph.agentUser?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,identityParentId" | Get-GraphPage | Format-Agent -ObjectType "AgentUser"
    "$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application'&`$search=`"displayName:Microsoft Copilot Studio`"" | Get-GraphPage -Eventual | Format-Agent -ObjectType "CopilotStudioApp"
) | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
