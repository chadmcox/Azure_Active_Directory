<#PSScriptInfo
.VERSION 2026.10
.GUID 0e83db9d-b81a-4b80-a4d4-d80dfc2ba9af
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
Summarizes non-interactive sign-ins (apps and token refreshes) by country and region, to find tokens being used from unexpected places.
url: Using the location condition in a Conditional Access policy - https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-assignment-network
#>
<#
.SYNOPSIS
    Exports a non-interactive sign-in summary by country.
.EXAMPLE
    .\Get-NonInteractiveSignInLocations.ps1 -Environment Global -Days 7
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
$filter = "createdDateTime ge $since and signInEventTypes/any(t: t eq 'nonInteractiveUser')"
$file = Join-Path $Path "entra_noninteractive_signin_locations.csv"
Write-Host "Reading sign-ins"
"$script:Graph/auditLogs/signIns?`$filter=$filter" | Get-GraphPage |
    Group-Object { $_.location.countryOrRegion } |
    Select-Object @{ n = "Country"; e = { if ($_.Name) { $_.Name } else { "Unknown" } } },
        @{ n = "SignIns"; e = { $_.Count } },
        @{ n = "Failures"; e = { @($_.Group | Where-Object { $_.status.errorCode -ne 0 }).Count } },
        @{ n = "Users"; e = { @($_.Group.userPrincipalName | Sort-Object -Unique).Count } },
        @{ n = "Apps"; e = { ($_.Group.appDisplayName | Sort-Object -Unique | Select-Object -First 10) -join ";" } },
        @{ n = "LegacyAuth"; e = { @($_.Group | Where-Object { $_.clientAppUsed -notin "Browser", "Mobile Apps and Desktop clients", $null, "" }).Count } } |
    Sort-Object SignIns -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
