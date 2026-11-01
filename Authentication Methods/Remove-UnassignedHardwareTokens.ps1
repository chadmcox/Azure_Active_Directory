<#PSScriptInfo
.VERSION 2026.10
.GUID 900ab870-26d8-48be-b6b3-294083763d02
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
Deletes hardware OATH tokens that are not assigned to anyone, from a reviewed Get-UnassignedHardwareTokens.ps1 report or found live. Runs interactively or as an Azure Automation runbook with a managed identity.
url: How to manage hardware OATH tokens in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens
#>
<#
.SYNOPSIS
    Removes unassigned hardware OATH tokens.
.DESCRIPTION
    Replaces the -IncludeUnassignedTokens switch that was on Remove-StaleAuthMethods.ps1. Every token is
    checked again before deletion, so a token assigned after the report was made is skipped. A deleted
    token's secret is gone; upload it again to reuse the token.
.PARAMETER CsvPath
    A reviewed Get-UnassignedHardwareTokens.ps1 report. Without it, unassigned tokens are found live.
.PARAMETER MaxRemovals
    Stop after this many tokens, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-UnassignedHardwareTokens.ps1 -Environment Global -CsvPath .\entra_unassigned_hardware_tokens.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$MaxRemovals = 25,
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

function Remove-Token {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Token)
    process {
        $action = if ($PSCmdlet.ShouldProcess("$($Token.manufacturer) $($Token.serialNumber)", "Delete hardware OATH token")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/directory/authenticationMethodDevices/hardwareOathDevices/$($Token.id)" -Method DELETE
            "Deleted"
        } else { "WhatIf" }
        $Token | Select-Object id, serialNumber, manufacturer, model, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Policy.ReadWrite.AuthenticationMethod" -Identity:$Identity

$wanted = if ($CsvPath) { Import-Csv $CsvPath | Group-Object id -AsHashTable -AsString } else { $null }
$results = "$script:Graph/directory/authenticationMethodDevices/hardwareOathDevices" | Get-GraphPage |
    Where-Object { -not $_.assignedTo -and (-not $wanted -or $wanted.ContainsKey($_.id)) } |
    Select-Object -First $MaxRemovals | Remove-Token
$results | Format-Table serialNumber, manufacturer, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_unassigned_hardware_tokens_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
