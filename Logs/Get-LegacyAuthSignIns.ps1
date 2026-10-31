<#PSScriptInfo
.VERSION 2026.10
.GUID 3efee655-2e57-408d-8c11-55d93476ccc6
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
Finds sign-ins that used legacy (basic) authentication clients such as IMAP, POP, ActiveSync and older Office clients, grouped by user, app and client.
url: Identify and block legacy authentication - https://learn.microsoft.com/en-us/entra/identity/conditional-access/block-legacy-authentication
#>
<#
.SYNOPSIS
    Summarizes legacy authentication sign-ins.
.DESCRIPTION
    Replaces findBasicAuthExchangeOnline, findBasicAuthSharepointOnline and findBasicAuthSkypeforBusinessOnline.
.EXAMPLE
    .\Get-LegacyAuthSignIns.ps1 -Environment Global -Days 14
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

$legacyClients = "Exchange ActiveSync", "IMAP4", "POP3", "Authenticated SMTP", "Exchange Web Services", "Other clients",
    "Exchange Online PowerShell", "MAPI Over HTTP", "Offline Address Book", "Outlook Anywhere (RPC over HTTP)", "Reporting Web Services", "AutoDiscover"
$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_legacy_auth_signins.csv"
$legacyClients | ForEach-Object {
    "$script:Graph/auditLogs/signIns?`$filter=createdDateTime ge $since and clientAppUsed eq '$_'" | Get-GraphPage
} | Group-Object userPrincipalName, appDisplayName, clientAppUsed |
    Select-Object @{ n = "UserPrincipalName"; e = { $_.Group[0].userPrincipalName } },
        @{ n = "App"; e = { $_.Group[0].appDisplayName } },
        @{ n = "ClientApp"; e = { $_.Group[0].clientAppUsed } },
        @{ n = "SignIns"; e = { $_.Count } },
        @{ n = "Successful"; e = { @($_.Group | Where-Object { $_.status.errorCode -eq 0 }).Count } },
        @{ n = "IpAddresses"; e = { ($_.Group.ipAddress | Sort-Object -Unique) -join ";" } },
        @{ n = "LastSeen"; e = { $_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1 } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
