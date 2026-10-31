<#PSScriptInfo
.VERSION 2026.10
.GUID 6ec3f720-e0a0-4b26-a0fe-faecaa1c429d
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
Lists every lifecycle workflow (joiner, mover and leaver automation) with whether it's on and scheduled, its tasks, and the results of its recent runs, including failed users.
url: What are lifecycle workflows - https://learn.microsoft.com/en-us/entra/id-governance/what-are-lifecycle-workflows
url: List workflows - https://learn.microsoft.com/en-us/graph/api/identitygovernance-lifecycleworkflowscontainer-list-workflows?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports lifecycle workflows and their recent run results.
.DESCRIPTION
    Needs Microsoft Entra ID Governance.
.PARAMETER Days
    Days of run history to summarize. Default 30.
.EXAMPLE
    .\Get-LifecycleWorkflows.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 30,
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

function Format-Workflow {
    param([Parameter(ValueFromPipeline)]$Workflow)
    process {
        $w = $Workflow
        $runs = @(try { "$script:Graph/identityGovernance/lifecycleWorkflows/workflows/$($w.id)/runs?`$filter=startedDateTime ge $since" | Get-GraphPage } catch { })
        $w | Select-Object displayName, id, category, isEnabled, isSchedulingEnabled, lastModifiedDateTime,
            @{ n = "Tasks"; e = { ($w.tasks | ForEach-Object { $_.displayName }) -join ";" } },
            @{ n = "Runs"; e = { $runs.Count } },
            @{ n = "UsersProcessed"; e = { ($runs | Measure-Object -Property totalUsersCount -Sum).Sum } },
            @{ n = "UsersFailed"; e = { ($runs | Measure-Object -Property failedUsersCount -Sum).Sum } },
            @{ n = "LastRun"; e = { $runs.startedDateTime | Sort-Object -Descending | Select-Object -First 1 } },
            @{ n = "Finding"; e = { if (-not $_.isEnabled) { "Disabled" } elseif (-not $_.isSchedulingEnabled) { "Not scheduled" } elseif (($runs | Measure-Object -Property failedUsersCount -Sum).Sum -gt 0) { "Has failures" } } }
    }
}

Connect-Cloud -Scopes "LifecycleWorkflows.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_lifecycle_workflows.csv"
@(try { "$script:Graph/identityGovernance/lifecycleWorkflows/workflows?`$expand=tasks" | Get-GraphPage } catch { Write-Warning "Lifecycle workflows: $($_.Exception.Message)" }) |
    Format-Workflow | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
