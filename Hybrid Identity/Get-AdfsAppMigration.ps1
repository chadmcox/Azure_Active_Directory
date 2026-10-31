<#PSScriptInfo
.VERSION 2026.10
.GUID e0bf0e8d-1125-4be0-bf86-445722fe7969
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
Lists the AD FS relying parties seen by Entra Connect Health with their sign-in volume and whether each one is ready to move to Microsoft Entra ID, to plan the AD FS application migration.
url: AD FS application migration - https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/migrate-adfs-application-activity
url: getRelyingPartyDetailedSummary - https://learn.microsoft.com/en-us/graph/api/reportroot-getrelyingpartydetailedsummary?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports AD FS relying parties and their migration readiness.
.DESCRIPTION
    Needs the Entra Connect Health agent for AD FS. Returns nothing if AD FS isn't monitored.
.EXAMPLE
    .\Get-AdfsAppMigration.ps1 -Environment Global -Period D30
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("D1", "D7", "D30")][string]$Period = "D30",
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

$file = Join-Path $Path "adfs_app_migration.csv"
"$script:Graph/reports/getRelyingPartyDetailedSummary(period='$Period')" | Get-GraphPage |
    Select-Object relyingPartyName, relyingPartyId, serviceId, migrationStatus, successfulSignInCount, failedSignInCount, totalSignInCount, signInSuccessRate,
        uniqueUserCount, @{ n = "ReplyUrls"; e = { $_.replyUrls -join ";" } },
        @{ n = "MigrationIssues"; e = { ($_.migrationValidationDetails | Where-Object { $_.value -ne "0" } | ForEach-Object { "$($_.name)=$($_.value)" }) -join ";" } } |
    Sort-Object totalSignInCount -Descending |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
