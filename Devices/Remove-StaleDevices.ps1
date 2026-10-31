<#PSScriptInfo
.VERSION 2026.10
.GUID 0fbbdbb1-3637-4404-8191-f3e89210fb61
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
Cleans up stale devices the way Microsoft recommends: first disables devices with no activity, then deletes devices that are already disabled and still inactive. Skips hybrid joined (synced) and Windows Autopilot devices. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Manage stale devices in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices
#>
<#
.SYNOPSIS
    Disables or deletes stale devices.
.DESCRIPTION
    Every device is checked again before it is changed. Deleting a device also deletes its BitLocker
    recovery keys, so run -Action Disable first and wait (for example 30 days) before -Action Delete.
.PARAMETER CsvPath
    A reviewed Get-StaleDevices.ps1 report. Without it, stale devices are found live.
.PARAMETER Action
    Disable - disable enabled stale devices. Delete - delete stale devices that are already disabled.
.PARAMETER Days
    Days without activity. Default 180.
.PARAMETER MaxRemovals
    Stop after this many devices, as a safety limit. Default 50.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleDevices.ps1 -Environment Global -CsvPath .\entra_stale_devices.csv -Action Disable -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [ValidateSet("Disable", "Delete")][string]$Action = "Disable",
    [int]$Days = 180,
    [int]$MaxRemovals = 50,
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
    $select = "id,deviceId,displayName,accountEnabled,operatingSystem,trustType,onPremisesSyncEnabled,registrationDateTime,approximateLastSignInDateTime,physicalIds"
    if ($CsvPath) {
        Import-Csv $CsvPath | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/devices/$($_.id)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/devices?`$select=$select&`$top=999" | Get-GraphPage
    }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Device)
    process {
        $last = $Device.approximateLastSignInDateTime
        $stale = (-not $Device.registrationDateTime -or [datetime]$Device.registrationDateTime -lt $cutoff) -and (-not $last -or [datetime]$last -lt $cutoff)
        $allowed = -not $Device.onPremisesSyncEnabled -and $Device.physicalIds -notmatch "\[ZTDID\]"
        $ready = if ($Action -eq "Disable") { $Device.accountEnabled } else { -not $Device.accountEnabled }
        if ($stale -and $allowed -and $ready) { $Device }
    }
}

function Update-Device {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Device)
    process {
        $result = if (-not $PSCmdlet.ShouldProcess($Device.displayName, "$Action device")) { "WhatIf" }
            elseif ($Action -eq "Disable") {
                Invoke-MgGraphRequest -Uri "$script:Graph/devices/$($Device.id)" -Method PATCH -Body (@{ accountEnabled = $false } | ConvertTo-Json) -ContentType "application/json"
                "Disabled"
            } else {
                Invoke-MgGraphRequest -Uri "$script:Graph/devices/$($Device.id)" -Method DELETE
                "Deleted"
            }
        $Device | Select-Object id, deviceId, displayName, operatingSystem, trustType, registrationDateTime, approximateLastSignInDateTime, @{ n = "Action"; e = { $result } }
    }
}

Connect-Cloud -Scopes "Device.ReadWrite.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$results = Get-Candidates | Select-Stale | Select-Object -First $MaxRemovals | Update-Device
$results | Format-Table displayName, operatingSystem, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_devices_$($Action.ToLower()).csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
