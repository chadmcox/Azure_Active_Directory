<#PSScriptInfo
.VERSION 2026.10
.GUID a439d13f-e14e-45d7-83bb-dee78fd43829
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
Lists Microsoft Entra recommendations (the tenant's built-in best-practice findings) with their status, priority and how many resources each one affects.
url: What are Microsoft Entra recommendations - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/overview-recommendations
url: List recommendations - https://learn.microsoft.com/en-us/graph/api/directory-list-recommendations?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports Microsoft Entra recommendations and their affected resources.
.DESCRIPTION
    Writes the recommendations and, for active ones, every affected resource in a second file.
.EXAMPLE
    .\Get-EntraRecommendations.ps1 -Environment Global
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

function Get-Impacted {
    param([Parameter(ValueFromPipeline)]$Recommendation)
    process {
        $r = $Recommendation
        "$script:Graph/directory/recommendations/$($r.id)/impactedResources" | Get-GraphPage |
            Select-Object @{ n = "Recommendation"; e = { $r.displayName } }, displayName, id, resourceType, status, addedDateTime, owner, portalUrl
    }
}

Connect-Cloud -Scopes "DirectoryRecommendations.Read.All"

$recommendations = @("$script:Graph/directory/recommendations" | Get-GraphPage)
$recommendations | Select-Object displayName, status, priority, category, impactType, recommendationType, lastCheckedDateTime, postponeUntilDateTime,
    @{ n = "FeatureAreas"; e = { $_.featureAreas -join ";" } },
    @{ n = "ImpactedResources"; e = { @("$script:Graph/directory/recommendations/$($_.id)/impactedResources?`$select=id" | Get-GraphPage).Count } },
    @{ n = "Benefits"; e = { $_.benefits } } |
    Sort-Object status, priority |
    Export-Csv (Join-Path $Path "entra_recommendations.csv") -NoTypeInformation
$recommendations | Where-Object { $_.status -eq "active" } | Get-Impacted |
    Export-Csv (Join-Path $Path "entra_recommendations_impacted.csv") -NoTypeInformation
Write-Host "Results: $Path\entra_recommendations*.csv"
