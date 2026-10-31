<#PSScriptInfo
.VERSION 2026.10
.GUID a915fbed-19f9-4ffc-96eb-665cdae5ec6b
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
Shows the number of successful and failed sign-ins for each application over the last 7 or 30 days.
url: getAzureADApplicationSignInSummary - https://learn.microsoft.com/en-us/graph/api/reportroot-getazureadapplicationsigninsummary?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports the application sign-in summary report.
.DESCRIPTION
    Replaces exportAADSummaryforApplicationSignins.
.EXAMPLE
    .\Get-AppSignInSummary.ps1 -Environment Global -Period D30
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("D7", "D30")][string]$Period = "D30",
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

Connect-Cloud -Scopes "Reports.Read.All"

$file = Join-Path $Path "entra_app_signin_summary_$Period.csv"
"$script:Graph/reports/getAzureADApplicationSignInSummary(period='$Period')" | Get-GraphPage |
    Select-Object @{ n = "AppId"; e = { $_.id } }, appDisplayName, successfulSignInCount, failedSignInCount, successPercentage |
    Sort-Object successfulSignInCount -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
