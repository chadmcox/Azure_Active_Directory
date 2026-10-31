<#PSScriptInfo
.VERSION 2026.10
.GUID 094cc5df-3668-4acf-a9d5-903d025670cf
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
Finds stale custom domains: domains that were added but never verified, and verified domains that no user, group or app uses any more.
url: Manage custom domain names - https://learn.microsoft.com/en-us/entra/identity/users/domains-manage
url: List domainNameReferences - https://learn.microsoft.com/en-us/graph/api/domain-list-domainnamereferences?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a stale domain report.
.DESCRIPTION
    The default, initial (onmicrosoft.com) and federated domains are never reported as removable.
    Review the CSV, remove rows to keep, then pass it to Remove-StaleDomains.ps1 -CsvPath.
    Get-DomainUsage.ps1 shows every object that still uses a domain.
.EXAMPLE
    .\Get-StaleDomains.ps1 -Environment Global
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

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$Domain)
    process {
        if ($Domain.isDefault -or $Domain.isInitial) { return }
        $inUse = [bool]("$script:Graph/domains/$($Domain.id)/domainNameReferences?`$select=id" | Get-GraphPage | Select-Object -First 1)
        $reason = if (-not $Domain.isVerified) { "NotVerified" } elseif (-not $inUse) { "NotUsed" }
        if (-not $reason) { return }
        $Domain | Select-Object id, isVerified, authenticationType, isRoot,
            @{ n = "SupportedServices"; e = { $_.supportedServices -join ";" } },
            @{ n = "StaleReason"; e = { $reason } },
            @{ n = "Remediation"; e = {
                if ($_.authenticationType -eq "Federated") { "Review - federated domain" }
                elseif ($inUse) { "Move objects off the domain first (Get-DomainUsage.ps1)" }
                else { "Remove-StaleDomains.ps1" } } }
    }
}

Connect-Cloud -Scopes "Domain.Read.All", "Directory.Read.All"

$file = Join-Path $Path "entra_stale_domains.csv"
"$script:Graph/domains" | Get-GraphPage | Select-Stale | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
