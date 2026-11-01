<#PSScriptInfo
.VERSION 2026.10
.GUID 8652561a-e6e0-4012-b22b-0a52d98c1392
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
Checks every enabled Windows device for a Windows LAPS local admin password backup and a BitLocker recovery key in Entra ID, so devices that couldn't be recovered can be found before they're needed.
url: Windows LAPS with Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/devices/howto-manage-local-admin-passwords
url: List bitlockerRecoveryKeys - https://learn.microsoft.com/en-us/graph/api/bitlocker-list-recoverykeys?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Reports LAPS and BitLocker key backup per Windows device.
.DESCRIPTION
    Only reads which devices have keys and when they were backed up; it never reads the passwords or
    recovery keys themselves. Reading key metadata needs the Cloud Device Administrator,
    Intune Administrator or Security Reader role.
.EXAMPLE
    .\Get-DeviceKeyCoverage.ps1 -Environment Global
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

Connect-Cloud -Scopes "Device.Read.All", "DeviceLocalCredential.ReadBasic.All", "BitlockerKey.ReadBasic.All"

$laps = @{}
try { "$script:Graph/directory/deviceLocalCredentials" | Get-GraphPage | ForEach-Object { $laps[[string]$_.id] = $_.lastBackupDateTime } } catch { Write-Warning "LAPS: $($_.Exception.Message)" }
$bitlocker = @{}
try {
    "$script:Graph/informationProtection/bitlocker/recoveryKeys" | Get-GraphPage | Sort-Object createdDateTime |
        ForEach-Object { $bitlocker[[string]$_.deviceId] = $_.createdDateTime }
} catch { Write-Warning "BitLocker: $($_.Exception.Message)" }

$file = Join-Path $Path "entra_device_key_coverage.csv"
"$script:Graph/devices?`$filter=operatingSystem eq 'Windows' and accountEnabled eq true&`$select=id,deviceId,displayName,trustType,operatingSystemVersion,approximateLastSignInDateTime,isManaged&`$count=true" |
    Get-GraphPage -Eventual |
    Select-Object displayName, deviceId, trustType, operatingSystemVersion, isManaged, approximateLastSignInDateTime,
        @{ n = "LapsBackup"; e = { $laps[[string]$_.deviceId] } },
        @{ n = "BitLockerKeyBackup"; e = { $bitlocker[[string]$_.deviceId] } },
        @{ n = "Finding"; e = {
            @(
                if (-not $laps.ContainsKey([string]$_.deviceId)) { "No LAPS password" }
                if (-not $bitlocker.ContainsKey([string]$_.deviceId)) { "No BitLocker key" }
            ) -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
