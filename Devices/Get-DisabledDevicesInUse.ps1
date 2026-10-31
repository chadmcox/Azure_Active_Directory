<#PSScriptInfo
.VERSION 2026.10
.GUID 49acd468-48f4-4335-8e3a-dca21bfa1499
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
Finds disabled devices that people are still trying to use, from sign-ins that failed with error 135011 (device disabled), so they can be re-enabled or the users helped before devices are deleted.
url: Sign-in error code 135011 - https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes
#>
<#
.SYNOPSIS
    Lists disabled devices still in use.
.DESCRIPTION
    Replaces Devices\AzureADModule\GetDisabledAADDevicesStillInUse.
.EXAMPLE
    .\Get-DisabledDevicesInUse.ps1 -Environment Global -Days 14
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 7,
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

Connect-Cloud -Scopes "AuditLog.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_disabled_devices_in_use.csv"
"$script:Graph/auditLogs/signIns?`$filter=createdDateTime ge $since and status/errorCode eq 135011" | Get-GraphPage |
    Group-Object { $_.deviceDetail.deviceId }, userPrincipalName |
    Select-Object @{ n = "DeviceName"; e = { $_.Group[0].deviceDetail.displayName } },
        @{ n = "DeviceId"; e = { $_.Group[0].deviceDetail.deviceId } },
        @{ n = "UserPrincipalName"; e = { $_.Group[0].userPrincipalName } },
        @{ n = "Apps"; e = { ($_.Group.appDisplayName | Sort-Object -Unique) -join ";" } },
        @{ n = "Attempts"; e = { $_.Count } },
        @{ n = "LastAttempt"; e = { $_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1 } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
