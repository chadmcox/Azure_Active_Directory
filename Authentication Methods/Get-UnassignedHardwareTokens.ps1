<#PSScriptInfo
.VERSION 2026.10
.GUID b57d42cb-4b4b-4fd8-b089-b6e3558b5a79
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
Lists hardware OATH tokens that are uploaded to Entra ID but not assigned to anyone, so they can be assigned or removed.
url: How to manage hardware OATH tokens in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens
#>
<#
.SYNOPSIS
    Creates a report of unassigned hardware OATH tokens.
.DESCRIPTION
    Review the CSV, remove rows for tokens to keep, then pass it to Remove-UnassignedHardwareTokens.ps1 -CsvPath.
.EXAMPLE
    .\Get-UnassignedHardwareTokens.ps1 -Environment Global
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

Connect-Cloud -Scopes "Policy.Read.AuthenticationMethod"

$file = Join-Path $Path "entra_unassigned_hardware_tokens.csv"
"$script:Graph/directory/authenticationMethodDevices/hardwareOathDevices" | Get-GraphPage |
    Where-Object { -not $_.assignedTo } |
    Select-Object id, serialNumber, manufacturer, model, status, createdDateTime, lastUsedDateTime, hashFunction, timeIntervalInSeconds |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
