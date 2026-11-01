<#PSScriptInfo
.VERSION 2026.10
.GUID fff8bbd0-a5fc-4896-8016-c12d1d550818
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
Summarizes sign-ins by country and region, with how many users and failures come from each, to find traffic from places where there's no business reason to sign in and block them with a location-based Conditional Access policy.
url: Using the location condition in a Conditional Access policy - https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-assignment-network
#>
<#
.SYNOPSIS
    Exports a sign-in summary by country.
.DESCRIPTION
    Reads interactive sign-ins for the chosen number of days. For non-interactive sign-ins use
    Get-NonInteractiveSignInLocations.ps1.
.EXAMPLE
    .\Get-SignInLocations.ps1 -Environment Global -Days 7
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
$filter = "createdDateTime ge $since"
$file = Join-Path $Path "entra_signin_locations.csv"
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
