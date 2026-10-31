<#PSScriptInfo
.VERSION 2026.10
.GUID 97461721-1afe-4b5e-8f2d-9240d8db019b
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
Exports Microsoft Secure Score recommendations with rank, score impact, points achieved, status, category and product, in the same layout as the Defender portal export.
url: List secureScores - https://learn.microsoft.com/en-us/graph/api/security-list-securescores?view=graph-rest-beta
url: List secureScoreControlProfiles - https://learn.microsoft.com/en-us/graph/api/security-list-securescorecontrolprofiles?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports the current Microsoft Secure Score recommendations.
.DESCRIPTION
    Replaces Microsoft Secure Score\get-MicrosoftSecureScorefromGraph.
.EXAMPLE
    .\Get-SecureScore.ps1 -Environment Global
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

function Get-ProductName {
    param([string]$Service)
    $names = @{
        "Admincenter" = "Microsoft Admin Center"; "Azure ATP" = "Defender for Identity"; "AzureAD" = "Microsoft Entra ID"
        "EXO" = "Exchange Online"; "FORMS" = "Microsoft Forms"; "Intune" = "Intune"; "MCAS" = "Microsoft Defender for Cloud Apps"
        "MDATP" = "Defender for Endpoint"; "MDO" = "Defender for Office"; "MIP" = "Microsoft Information Protection"
        "MS Teams" = "Microsoft Teams"; "SPO" = "SharePoint Online"; "SWAY" = "Microsoft Sway"
    }
    if ($names.ContainsKey($Service)) { $names[$Service] } else { $Service }
}

function Format-Control {
    param([Parameter(ValueFromPipeline)]$Control)
    process {
        $c = $Control
        $controlProfile = $profiles[$c.controlName]
        if (-not $controlProfile) { $controlProfile = try { Invoke-MgGraphRequest -Uri "$script:Graph/security/secureScoreControlProfiles/$($c.controlName)" -OutputType PSObject -ErrorAction Stop } catch { return } }
        $controlProfile | Select-Object @{ n = "Rank"; e = { $_.rank } },
            @{ n = "Recommended action"; e = { $_.title } },
            @{ n = "Score impact"; e = { "{0:P2}" -f ([double]$_.maxScore / [double]$score.maxScore) } },
            @{ n = "Points achieved"; e = { "$($c.score) out of $($_.maxScore)" } },
            @{ n = "Status"; e = { if ([double]$c.score -ge [double]$_.maxScore) { "Completed" } else { "To address" } } },
            @{ n = "Category"; e = { $c.controlCategory } },
            @{ n = "Product"; e = { Get-ProductName -Service $_.service } },
            @{ n = "Last synced"; e = { $c.lastSynced } }
    }
}

Connect-Cloud -Scopes "SecurityEvents.Read.All"

Write-Host "Getting Secure Score control profiles"
$profiles = "$script:Graph/security/secureScoreControlProfiles" | Get-GraphPage | Group-Object id -AsHashTable -AsString
Write-Host "Getting the latest Secure Score"
$score = Invoke-MgGraphRequest -Uri "$script:Graph/security/secureScores?`$top=1" -OutputType PSObject | Select-Object -ExpandProperty value | Select-Object -First 1
$file = Join-Path $Path "microsoft_secure_score.csv"
$score.controlScores | Format-Control | Sort-Object { [int]$_.Rank } | Export-Csv $file -NoTypeInformation
Write-Host "Secure Score: $($score.currentScore) of $($score.maxScore). Results: $file"
