<#PSScriptInfo
.VERSION 2026.10
.GUID 4b7d367c-aa7b-44ef-9b05-1d1cce00017d
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
Makes sure the emergency access (break glass) accounts are excluded from every Conditional Access policy and adds them where they are missing. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Manage emergency access accounts - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access
#>
<#
.SYNOPSIS
    Adds break glass accounts to every Conditional Access policy's exclusions.
.DESCRIPTION
    Replaces add-BreakGlasstoConditionalAccessPolicyExclusion and Maintenance Task\runbook-addAADBreakGlasstoConditionalAccessPolicy.
.PARAMETER BreakGlassAccount
    UPNs or object IDs of the emergency access accounts.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Add-BreakGlassExclusions.ps1 -Environment Global -BreakGlassAccount "<break glass UPN 1>", "<break glass UPN 2>" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string[]]$BreakGlassAccount,
    [switch]$Identity
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

function Add-Exclusion {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        $missing = $accountIds | Where-Object { $_ -notin $Policy.conditions.users.excludeUsers }
        if (-not $missing) { Write-Output "OK      $($Policy.displayName)"; return }
        if ($PSCmdlet.ShouldProcess($Policy.displayName, "Exclude $($missing -join ', ')")) {
            $body = @{ conditions = @{ users = @{ excludeUsers = @(@($Policy.conditions.users.excludeUsers) + @($missing) | Where-Object { $_ }) } } } | ConvertTo-Json -Depth 5
            Invoke-MgGraphRequest -Uri "$script:Graph/identity/conditionalAccess/policies/$($Policy.id)" -Method PATCH -Body $body -ContentType "application/json"
            Write-Output "Updated $($Policy.displayName)"
        }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "User.Read.All" -Identity:$Identity

$accountIds = $BreakGlassAccount | ForEach-Object { (Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_)?`$select=id" -OutputType PSObject).id }
"$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage | Add-Exclusion
