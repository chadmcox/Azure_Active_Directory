<#PSScriptInfo
.VERSION 2026.10
.GUID f30af9e7-5c1a-4274-ad1e-21b749b2cf43
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
Lists everyone who reports to a manager, directly or through other managers, all the way down the org chart.
url: List directReports - https://learn.microsoft.com/en-us/graph/api/user-list-directreports?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports a manager's whole reporting tree.
.DESCRIPTION
    Replaces get-AADUsersDirectReports.
.EXAMPLE
    .\Get-UserDirectReports.ps1 -Environment Global -Manager "<manager UPN>"
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string]$Manager,
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

function Get-Reports {
    param([Parameter(ValueFromPipeline)]$Person, [int]$Level = 1)
    process {
        $boss = $Person
        "$script:Graph/users/$($boss.id)/directReports?`$select=id,displayName,userPrincipalName,onPremisesSamAccountName,department,jobTitle" | Get-GraphPage |
            Where-Object { -not $seen.ContainsKey($_.id) } | ForEach-Object {
            $seen[$_.id] = $true
            $_ | Select-Object id, displayName, userPrincipalName, onPremisesSamAccountName, department, jobTitle,
                @{ n = "Manager"; e = { $boss.displayName } }, @{ n = "Level"; e = { $Level } }
            $_ | Get-Reports -Level ($Level + 1)
        }
    }
}

Connect-Cloud -Scopes "User.Read.All"

$seen = @{}
$top = Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Manager)?`$select=id,displayName,userPrincipalName" -OutputType PSObject
$file = Join-Path $Path "$($top.userPrincipalName)_reports.csv"
$top | Get-Reports | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
