<#PSScriptInfo
.VERSION 2026.10
.GUID 19af869b-a74c-4f48-adba-b896f5ca17dd
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
Backs up every Conditional Access policy and named location to JSON files, one file per object, so a policy can be compared or restored after a change.
url: List policies - https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Saves Conditional Access policies and named locations as JSON.
.DESCRIPTION
    Replaces the -BackupJson switch that was on Get-CAPolicyReport.ps1.
.EXAMPLE
    .\Backup-CAPolicies.ps1 -Environment Global
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

function Save-Json {
    param([Parameter(ValueFromPipeline)]$Item, [string]$Folder)
    process {
        $name = ($Item.displayName -replace '[\\/:*?"<>|]', "_")
        $Item | ConvertTo-Json -Depth 20 | Out-File (Join-Path $Folder "$name.json")
    }
}

Connect-Cloud -Scopes "Policy.Read.All"

$root = Join-Path $Path "CA_Backup_$(Get-Date -Format yyyy-MM-dd-HHmm)"
$policyFolder = New-Item -ItemType Directory -Path (Join-Path $root "Policies") -Force
$locationFolder = New-Item -ItemType Directory -Path (Join-Path $root "NamedLocations") -Force
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage | Save-Json -Folder $policyFolder
"$script:Graph/identity/conditionalAccess/namedLocations" | Get-GraphPage | Save-Json -Folder $locationFolder
Write-Host "Results: $root"
