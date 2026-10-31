<#PSScriptInfo
.VERSION 2026.10
.GUID 680b44e4-34c9-4a3e-84ba-d5a9a84a1804
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
Lists every enterprise app that has automatic user provisioning set up, with the job status, last run, quarantine state and error counts, so failing or quarantined provisioning can be fixed.
url: What is app provisioning in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/app-provisioning/user-provisioning
url: List synchronization jobs - https://learn.microsoft.com/en-us/graph/api/synchronization-synchronization-list-jobs?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports the provisioning job status of every enterprise app.
.DESCRIPTION
    Checks each enabled enterprise app for provisioning jobs, which takes a while in large tenants.
    Apps without provisioning are left out.
.EXAMPLE
    .\Get-AppProvisioningStatus.ps1 -Environment Global
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

function Get-Jobs {
    param([Parameter(ValueFromPipeline)]$App)
    process {
        $a = $App
        @(try { "$script:Graph/servicePrincipals/$($a.id)/synchronization/jobs" | Get-GraphPage } catch { }) |
            Select-Object @{ n = "App"; e = { $a.displayName } }, @{ n = "AppId"; e = { $a.appId } }, @{ n = "JobId"; e = { $_.id } },
                @{ n = "Template"; e = { $_.templateId } },
                @{ n = "State"; e = { $_.schedule.state } },
                @{ n = "Status"; e = { $_.status.code } },
                @{ n = "LastRun"; e = { $_.status.lastExecution.timeEnded } },
                @{ n = "LastRunState"; e = { $_.status.lastExecution.state } },
                @{ n = "Quarantined"; e = { [bool]$_.status.quarantine } },
                @{ n = "QuarantineReason"; e = { $_.status.quarantine.reason } },
                @{ n = "SuccessiveFailures"; e = { $_.status.countSuccessiveCompleteFailures } },
                @{ n = "LastSuccessfulRun"; e = { $_.status.lastSuccessfulExecution.timeEnded } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "Synchronization.Read.All"

$file = Join-Path $Path "entra_app_provisioning_status.csv"
Write-Host "Checking enterprise apps for provisioning jobs"
"$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$select=id,appId,displayName" |
    Get-GraphPage | Get-Jobs | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
