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
Lists agent identities in Entra ID: agent service principals, agent users and Copilot Studio agent apps, with their last sign-in.
url: What are agent identities - https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id
#>
<#
.SYNOPSIS
    Exports agent-related service principals and users.
.DESCRIPTION
    Replaces Agent 365\Get Agent Related Service Principals, Agent 365\Get agent related user identities
    and Applications\get-EntraCopilotServicePrincipals.
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

function Format-Agent {
    param([Parameter(ValueFromPipeline)]$Agent, [string]$Kind)
    process {
        $Agent | Select-Object @{ n = "Kind"; e = { $Kind } }, id, appId, displayName, userPrincipalName, servicePrincipalType,
            accountEnabled, publisherName, createdDateTime,
            @{ n = "LastSignInDateTime"; e = { if ($_.appId) { $lastSignIns[$_.appId].lastSignInActivity.lastSignInDateTime } else { $_.signInActivity.lastSignInDateTime } } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "User.Read.All", "AuditLog.Read.All"

$lastSignIns = @("$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { $lastSignIns = @{} }

$file = Join-Path $Path "entra_agent_identities.csv"
@(
    "$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'ServiceIdentity'" | Get-GraphPage | Format-Agent -Kind "AgentServicePrincipal"
    "$script:Graph/users/microsoft.graph.agentUser?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,signInActivity" | Get-GraphPage | Format-Agent -Kind "AgentUser"
    "$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application'&`$search=`"displayName:Microsoft Copilot Studio`"" | Get-GraphPage -Eventual | Format-Agent -Kind "CopilotStudioApp"
) | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
