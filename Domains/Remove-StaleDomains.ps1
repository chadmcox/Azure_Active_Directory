<#PSScriptInfo
.VERSION 2026.10
.GUID 78ca7607-61f0-4c59-88f1-32c3c733130c
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
Deletes stale custom domains: unverified domains and, with -IncludeVerified, verified domains nothing uses. Never touches the default, initial or federated domains or any domain still in use. Works from a reviewed Get-StaleDomains.ps1 report or finds them live.
url: Delete domain - https://learn.microsoft.com/en-us/graph/api/domain-delete?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes unverified and unused custom domains.
.DESCRIPTION
    Every domain is checked again before deletion. Graph refuses to delete a domain that is still
    referenced, so a domain that started being used after the report is skipped.
.PARAMETER CsvPath
    A reviewed Get-StaleDomains.ps1 report. Without it, stale domains are found live.
.PARAMETER IncludeVerified
    Also delete verified domains that nothing uses. By default only unverified domains are deleted.
.PARAMETER MaxRemovals
    Stop after this many domains, as a safety limit. Default 5.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleDomains.ps1 -Environment Global -CsvPath .\entra_stale_domains.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [switch]$IncludeVerified,
    [int]$MaxRemovals = 5,
    [switch]$Identity,
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

function Select-Removable {
    param([Parameter(ValueFromPipeline)]$Domain)
    process {
        if ($Domain.isDefault -or $Domain.isInitial -or $Domain.authenticationType -eq "Federated") { return }
        if ($wanted -and -not $wanted.ContainsKey($Domain.id)) { return }
        if ($Domain.isVerified -and -not $IncludeVerified) { return }
        $inUse = "$script:Graph/domains/$($Domain.id)/domainNameReferences?`$select=id" | Get-GraphPage | Select-Object -First 1
        if (-not $inUse) { $Domain }
    }
}

function Remove-Domain {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Domain)
    process {
        $action = if ($PSCmdlet.ShouldProcess($Domain.id, "Delete domain")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/domains/$($Domain.id)" -Method DELETE
            "Deleted"
        } else { "WhatIf" }
        $Domain | Select-Object id, isVerified, authenticationType, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Domain.ReadWrite.All", "Directory.Read.All" -Identity:$Identity

$wanted = if ($CsvPath) { Import-Csv $CsvPath | Group-Object id -AsHashTable -AsString } else { $null }
$results = "$script:Graph/domains" | Get-GraphPage | Select-Removable | Select-Object -First $MaxRemovals | Remove-Domain
$results | Format-Table id, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_domains_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
