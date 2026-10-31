<#PSScriptInfo
.VERSION 2026.10
.GUID f224f248-0453-40ab-ac71-7cce5b27d62b
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
Shows who added or changed certificates and secrets on app registrations and service principals, from the audit log.
url: Microsoft Entra audit log activity reference - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/reference-audit-activities
#>
<#
.SYNOPSIS
    Exports credential changes on apps and service principals.
.DESCRIPTION
    Replaces Logs\whoAddedCredstoSPAPP. The audit log does not show which credential was added, so the
    report lists each credential key ID found in the change.
.EXAMPLE
    .\Get-AppCredentialChanges.ps1 -Environment Global -Days 30
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

Connect-Cloud -Scopes "AuditLog.Read.All"

$activities = "Add service principal credentials", "Remove service principal credentials", "Update application – Certificates and secrets management "
$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_app_credential_changes.csv"
"$script:Graph/auditLogs/directoryAudits?`$filter=category eq 'ApplicationManagement' and activityDateTime ge $since" | Get-GraphPage |
    Where-Object { $_.activityDisplayName.Trim() -in ($activities | ForEach-Object { $_.Trim() }) } |
    Select-Object activityDateTime, activityDisplayName, result,
        @{ n = "ModifiedBy"; e = { if ($_.initiatedBy.user.userPrincipalName) { $_.initiatedBy.user.userPrincipalName } else { $_.initiatedBy.app.displayName } } },
        @{ n = "TargetId"; e = { ($_.targetResources | Select-Object -First 1).id } },
        @{ n = "Target"; e = { ($_.targetResources | Select-Object -First 1).displayName } },
        @{ n = "TargetType"; e = { ($_.targetResources | Select-Object -First 1).type } },
        @{ n = "KeyIds"; e = { ([regex]::Matches(($_.targetResources.modifiedProperties.newValue -join " "), "KeyIdentifier=([0-9a-fA-F-]{36})") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
