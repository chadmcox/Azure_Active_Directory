<#PSScriptInfo
.VERSION 2026.10
.GUID ecebf1c4-cf71-4924-9e39-241c5540bd39
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
Finds Microsoft first-party service principals that have owners assigned. Owners can add credentials to these apps and use their permissions.
url: List owners of a servicePrincipal - https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-owners?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Lists Microsoft built-in apps that have owners.
.DESCRIPTION
    Replaces get-BuiltinAPPOwners and AzureADModule\get-builtinAppwOwnerAssigned.
.EXAMPLE
    .\Get-MicrosoftAppsWithOwners.ps1 -Environment Global
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

Connect-Cloud -Scopes "Application.Read.All"

# Microsoft's public first-party app tenant.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
$file = Join-Path $Path "entra_microsoft_apps_with_owners.csv"
"$script:Graph/servicePrincipals?`$filter=appOwnerOrganizationId eq $microsoftTenantId&`$select=id,appId,displayName,publisherName,accountEnabled&`$expand=owners(`$select=id,displayName,userPrincipalName)" |
    Get-GraphPage -Eventual | Where-Object { $_.owners } |
    Select-Object id, appId, displayName, publisherName, accountEnabled,
        @{ n = "Owners"; e = { ($_.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
