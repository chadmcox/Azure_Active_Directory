<#PSScriptInfo
.VERSION 2026.10
.GUID 27f29156-ab3a-4011-97df-48d1f01d0316
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
Finds devices with no activity for a set number of days and says how to remediate each one: disable then delete in Entra, clean up in Active Directory for hybrid joined devices, or leave Windows Autopilot devices alone.
url: Manage stale devices in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices
#>
<#
.SYNOPSIS
    Creates a stale device report.
.DESCRIPTION
    Review the CSV, remove any devices to keep, then pass it to Remove-StaleDevices.ps1 -CsvPath.
    The activity timestamp is only updated about every 14 days, so use at least 90 days.
.PARAMETER Days
    Days without activity. Default 180.
.EXAMPLE
    .\Get-StaleDevices.ps1 -Environment Global -Days 180
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 180,
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

function Get-Remediation {
    param($Device)
    if ($Device.physicalIds -match "\[ZTDID\]") { return "Keep - Windows Autopilot device (remove from Autopilot first)" }
    if ($Device.onPremisesSyncEnabled) { return "Disable or delete the computer in Active Directory" }
    if ($Device.accountEnabled) { return "Disable" }
    "Delete"
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Device)
    process {
        $last = $Device.approximateLastSignInDateTime
        if (($Device.registrationDateTime -and [datetime]$Device.registrationDateTime -ge $cutoff) -or ($last -and [datetime]$last -ge $cutoff)) { return }
        $Device | Select-Object id, deviceId, displayName, accountEnabled, operatingSystem, operatingSystemVersion,
            @{ n = "JoinType"; e = { $joinTypes[$_.trustType] } },
            isManaged, isCompliant, onPremisesSyncEnabled, registrationDateTime, approximateLastSignInDateTime,
            @{ n = "DaysSinceLastActivity"; e = { if ($last) { [int]((Get-Date) - [datetime]$last).TotalDays } else { "Never" } } },
            @{ n = "Autopilot"; e = { [bool]($_.physicalIds -match "\[ZTDID\]") } },
            @{ n = "Owners"; e = { $_.registeredOwners.userPrincipalName -join ";" } },
            @{ n = "Remediation"; e = { Get-Remediation -Device $_ } }
    }
}

Connect-Cloud -Scopes "Device.Read.All"

$cutoff = (Get-Date).AddDays(-$Days)
$joinTypes = @{ AzureAd = "Microsoft Entra joined"; ServerAd = "Microsoft Entra hybrid joined"; Workplace = "Microsoft Entra registered" }
$file = Join-Path $Path "entra_stale_devices.csv"
Write-Host "Getting devices"
"$script:Graph/devices?`$select=id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,isManaged,isCompliant,onPremisesSyncEnabled,registrationDateTime,approximateLastSignInDateTime,physicalIds&`$expand=registeredOwners(`$select=id,userPrincipalName)&`$top=999" |
    Get-GraphPage | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
