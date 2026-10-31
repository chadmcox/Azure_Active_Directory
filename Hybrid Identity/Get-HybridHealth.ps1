<#PSScriptInfo
.VERSION 2026.10
.GUID c0e0ac77-2ada-4749-b91a-d17299d41d05
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
Checks the health of hybrid identity: last directory sync and how long ago it ran, sync features such as password hash sync and writeback, and every pass-through authentication agent, private network (application proxy) connector and provisioning agent with its version, status and whether its group has at least two for redundancy.
url: Microsoft Entra general operations guide reference - https://learn.microsoft.com/en-us/entra/architecture/ops-guide-ops
#>
<#
.SYNOPSIS
    Reports sync status, sync features and on-premises agent health.
.DESCRIPTION
    Covers the operations guide checks that Microsoft Graph can see: sync running on schedule,
    password hash sync turned on, components up to date (compare Version with the latest release),
    and at least two agents or connectors per group. Entra Connect server version and Connect Health
    alerts are not in Microsoft Graph; check those in the Entra admin center.
.EXAMPLE
    .\Get-HybridHealth.ps1 -Environment Global
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

function Get-Agents {
    param([string]$PublishingProfile, [string]$Kind)
    try {
        "$script:Graph/onPremisesPublishingProfiles/$PublishingProfile/agentGroups?`$expand=agents" | Get-GraphPage | ForEach-Object {
            $group = $_
            $group.agents | Select-Object @{ n = "Component"; e = { $Kind } }, @{ n = "Group"; e = { $group.displayName } },
                machineName, externalIp, status, @{ n = "Version"; e = { $_.version } },
                @{ n = "AgentsInGroup"; e = { @($group.agents).Count } },
                @{ n = "Redundant"; e = { @($group.agents | Where-Object { $_.status -eq "active" }).Count -ge 2 } }
        }
    } catch { Write-Warning "$($Kind): $($_.Exception.Message)" }
}

function Get-Connectors {
    try {
        "$script:Graph/onPremisesPublishingProfiles/applicationProxy/connectorGroups?`$expand=members" | Get-GraphPage | ForEach-Object {
            $group = $_
            $group.members | Select-Object @{ n = "Component"; e = { "Private network connector" } }, @{ n = "Group"; e = { $group.name } },
                machineName, externalIp, status, @{ n = "Version"; e = { $_.version } },
                @{ n = "AgentsInGroup"; e = { @($group.members).Count } },
                @{ n = "Redundant"; e = { @($group.members | Where-Object { $_.status -eq "active" }).Count -ge 2 } }
        }
    } catch { Write-Warning "Private network connectors: $($_.Exception.Message)" }
}

Connect-Cloud -Scopes "Organization.Read.All", "OnPremDirectorySynchronization.Read.All", "Directory.Read.All", "OnPremisesPublishingProfiles.ReadWrite.All"

$org = "$script:Graph/organization?`$select=onPremisesSyncEnabled,onPremisesLastSyncDateTime,onPremisesLastPasswordSyncDateTime" | Get-GraphPage | Select-Object -First 1
$sync = try { "$script:Graph/directory/onPremisesSynchronization" | Get-GraphPage | Select-Object -First 1 } catch { $null }

$summary = $org | Select-Object onPremisesSyncEnabled, onPremisesLastSyncDateTime,
    @{ n = "MinutesSinceLastSync"; e = { if ($_.onPremisesLastSyncDateTime) { [int]((Get-Date) - [datetime]$_.onPremisesLastSyncDateTime).TotalMinutes } } },
    @{ n = "SyncLate"; e = { $_.onPremisesSyncEnabled -and ((Get-Date) - [datetime]$_.onPremisesLastSyncDateTime).TotalMinutes -gt 60 } },
    onPremisesLastPasswordSyncDateTime,
    @{ n = "PasswordHashSync"; e = { $sync.features.passwordSyncEnabled } },
    @{ n = "PasswordWriteback"; e = { $sync.features.passwordWritebackEnabled } },
    @{ n = "DeviceWriteback"; e = { $sync.features.deviceWritebackEnabled } },
    @{ n = "GroupWriteback"; e = { $sync.features.groupWriteBackEnabled } },
    @{ n = "SoftMatchOnUpn"; e = { $sync.features.softMatchOnUpnEnabled } },
    @{ n = "BlockSoftMatch"; e = { $sync.features.blockSoftMatchEnabled } },
    @{ n = "AccidentalDeletionThreshold"; e = { $sync.configuration.accidentalDeletionPrevention.alertThreshold } }
$summary | Format-List | Out-Host

$file = Join-Path $Path "entra_hybrid_agents.csv"
@(
    Get-Agents -PublishingProfile "passthroughAuthentication" -Kind "Pass-through authentication agent"
    Get-Agents -PublishingProfile "provisioning" -Kind "Provisioning agent"
    Get-Connectors
) | Export-Csv $file -NoTypeInformation
$summary | Export-Csv (Join-Path $Path "entra_hybrid_sync_status.csv") -NoTypeInformation
Write-Host "Results: $file and $(Join-Path $Path 'entra_hybrid_sync_status.csv')"
