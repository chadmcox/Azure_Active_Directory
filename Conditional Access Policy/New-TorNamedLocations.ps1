<#PSScriptInfo
.VERSION 2026.10
.GUID 0fa9bd8f-8e88-4ca1-9473-31ac350bac05
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
Creates untrusted IP named locations from a public list of Tor exit nodes (1,000 addresses per location), for use in a Conditional Access block policy.
url: Create ipNamedLocation - https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-post-namedlocations?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates named locations for Tor exit node IP addresses.
.DESCRIPTION
    Replaces exampletocreatebadiplocations.
.PARAMETER SourceUrl
    A text list of IPv4 addresses.
.EXAMPLE
    .\New-TorNamedLocations.ps1 -Environment Global -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$SourceUrl = "https://raw.githubusercontent.com/SecOps-Institute/Tor-IP-Addresses/master/tor-exit-nodes.lst",
    [string]$NamePrefix = "Untrusted - Tor exit nodes IPv4"
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

function New-NamedLocation {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Batch)
    process {
        $name = "$NamePrefix $($Batch.Name)"
        if (-not $PSCmdlet.ShouldProcess($name, "Create named location with $($Batch.Count) addresses")) { return }
        $body = @{
            "@odata.type" = "#microsoft.graph.ipNamedLocation"
            displayName   = $name
            isTrusted     = $false
            ipRanges      = @($Batch.Group | ForEach-Object { @{ "@odata.type" = "#microsoft.graph.iPv4CidrRange"; cidrAddress = "$_/32" } })
        } | ConvertTo-Json -Depth 5
        Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/namedLocations" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject |
            Select-Object id, displayName
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess"

$addresses = (Invoke-WebRequest -Uri $SourceUrl -UseBasicParsing).Content |
    Select-String -Pattern "\b(?:\d{1,3}\.){3}\d{1,3}\b" -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
$index = 0
$addresses | Group-Object { [math]::Floor($script:index++ / 1000) + 1 } | New-NamedLocation
