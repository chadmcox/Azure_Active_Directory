<#PSScriptInfo
.VERSION 2026.10
.GUID 18bf582a-f85b-4a87-8f60-e52845ca1c08
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
Imports recommended Conditional Access policies from this repo's JSON file into the tenant in report-only mode, one at a time from a menu or all at once.
url: Conditional Access templates - https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common
#>
<#
.SYNOPSIS
    Imports the recommended Conditional Access policies as report-only.
.DESCRIPTION
    Replaces Import-AADRecommendedConditionalAccessPolicies. Policies are created in report-only mode
    with "Report Only - " in front of the name. Add your break glass exclusions afterwards
    (Add-BreakGlassExclusions.ps1).
.PARAMETER All
    Import every policy without showing the menu.
.EXAMPLE
    .\Import-RecommendedCAPolicies.ps1 -Environment Global
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$All,
    [string]$PolicyUrl = "https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/JSON/recommended_conditional_access_policies.json",
    [string]$TorLocationUrl = "https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/JSON/Tor_Exit_Notes.json"
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

function Add-TorLocation {
    $body = (Invoke-WebRequest -Uri $TorLocationUrl -UseBasicParsing).Content
    (Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/namedLocations" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject).id
}

function Import-Policy {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $name = "Report Only - $($Policy.displayName)"
        if (-not $PSCmdlet.ShouldProcess($name, "Create Conditional Access policy")) { return }
        if ($Policy.displayName -eq "All Users - Block Tor Exit Nodes") { $Policy.conditions.locations.includeLocations = @(Add-TorLocation) }
        $body = $Policy | Select-Object @{ n = "displayName"; e = { $name } }, @{ n = "state"; e = { "enabledForReportingButNotEnforced" } }, conditions, grantControls, sessionControls |
            ConvertTo-Json -Depth 20
        try {
            Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/policies" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
            Write-Output "Imported $name"
        } catch { Write-Warning "$name failed: $($_.Exception.Message)" }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Application.Read.All"

$policies = @(((Invoke-WebRequest -Uri $PolicyUrl -UseBasicParsing).Content | ConvertFrom-Json).value)
if ($All) { $policies | Import-Policy; return }

do {
    for ($i = 0; $i -lt $policies.Count; $i++) { Write-Host "$i - $($policies[$i].displayName)" }
    Write-Host "$($policies.Count) - Import all policies" -ForegroundColor Yellow
    $choice = Read-Host "Type a number to import, or exit"
    if ($choice -eq "$($policies.Count)") { $policies | Import-Policy }
    elseif ($choice -match "^\d+$" -and [int]$choice -lt $policies.Count) { $policies[[int]$choice] | Import-Policy }
} until ($choice -eq "exit")
