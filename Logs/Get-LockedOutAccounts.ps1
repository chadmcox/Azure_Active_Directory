<#PSScriptInfo
.VERSION 2026.10
.GUID 1f5b29ac-4229-4538-81db-2c0299c67348
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
Lists accounts that were locked out by smart lockout (sign-in error 50053) for a set number of days, with where the attempts came from, to spot password spray and brute force attacks.
url: Protect user accounts from attacks with Microsoft Entra smart lockout - https://learn.microsoft.com/en-us/entra/identity/authentication/howto-password-smart-lockout
#>
<#
.SYNOPSIS
    Summarizes smart lockout events by user.
.DESCRIPTION
    Replaces findAccountsWithLockoutEvents and the -ErrorCode parameter that was on Get-UserSignIns.ps1.
.EXAMPLE
    .\Get-LockedOutAccounts.ps1 -Environment Global -Days 7
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
$file = Join-Path $Path "entra_locked_out_accounts.csv"
"$script:Graph/auditLogs/signIns?`$filter=createdDateTime ge $since and status/errorCode eq 50053" | Get-GraphPage |
    Group-Object userPrincipalName |
    Select-Object @{ n = "UserPrincipalName"; e = { $_.Name } },
        @{ n = "Lockouts"; e = { $_.Count } },
        @{ n = "IpAddresses"; e = { ($_.Group.ipAddress | Sort-Object -Unique) -join ";" } },
        @{ n = "Countries"; e = { ($_.Group.location.countryOrRegion | Sort-Object -Unique) -join ";" } },
        @{ n = "Apps"; e = { ($_.Group.appDisplayName | Sort-Object -Unique) -join ";" } },
        @{ n = "ClientApps"; e = { ($_.Group.clientAppUsed | Sort-Object -Unique) -join ";" } },
        @{ n = "FirstSeen"; e = { $_.Group.createdDateTime | Sort-Object | Select-Object -First 1 } },
        @{ n = "LastSeen"; e = { $_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1 } } |
    Sort-Object Lockouts -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
