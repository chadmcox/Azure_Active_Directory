<#PSScriptInfo
.VERSION 2026.10
.GUID baa30e08-9de4-4ffd-a153-5958ebba85ec
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
Reports every device in Entra ID with its join type, OS, compliance, last sign-in and owner, and flags stale devices.
url: Manage stale devices in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices
#>
<#
.SYNOPSIS
    Exports a report of all devices.
.DESCRIPTION
    Replaces Devices\AzureADModule\AzureADDeviceScriptCollection and getAADDevicesStatus. Filter the
    CSV on JoinType (Microsoft Entra joined, hybrid joined, registered) and Stale.
.PARAMETER StaleDays
    Days without activity before a device is marked stale. Default 180.
.EXAMPLE
    .\Get-DeviceReport.ps1 -Environment Global -StaleDays 90
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$StaleDays = 180,
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

Connect-Cloud -Scopes "Device.Read.All"

$joinTypes = @{ AzureAd = "Microsoft Entra joined"; ServerAd = "Microsoft Entra hybrid joined"; Workplace = "Microsoft Entra registered" }
$file = Join-Path $Path "entra_devices.csv"
"$script:Graph/devices?`$select=id,deviceId,displayName,accountEnabled,approximateLastSignInDateTime,operatingSystem,operatingSystemVersion,trustType,profileType,isCompliant,isManaged,managementType,onPremisesSyncEnabled,onPremisesLastSyncDateTime,registrationDateTime,createdDateTime&`$expand=registeredOwners(`$select=id,userPrincipalName)&`$top=999" |
    Get-GraphPage |
    Select-Object id, deviceId, displayName, accountEnabled, operatingSystem, operatingSystemVersion,
        @{ n = "JoinType"; e = { if ($_.trustType) { $joinTypes[$_.trustType] } else { "Unknown" } } },
        trustType, profileType, isCompliant, isManaged, managementType, onPremisesSyncEnabled, onPremisesLastSyncDateTime,
        registrationDateTime, approximateLastSignInDateTime,
        @{ n = "DaysSinceLastSignIn"; e = { if ($_.approximateLastSignInDateTime) { [int]((Get-Date) - [datetime]$_.approximateLastSignInDateTime).TotalDays } } },
        @{ n = "Stale"; e = { -not $_.approximateLastSignInDateTime -or [datetime]$_.approximateLastSignInDateTime -lt (Get-Date).AddDays(-$StaleDays) } },
        @{ n = "Owners"; e = { $_.registeredOwners.userPrincipalName -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
