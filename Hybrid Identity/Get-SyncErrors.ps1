<#PSScriptInfo
.VERSION 2026.10
.GUID a5c09a1b-0733-485c-b620-932bf6506ec3
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
Lists users, groups and contacts with Entra Connect synchronization errors (for example duplicate proxy addresses or UPNs) and how long each error has been there, so errors older than 100 days can be cleaned up.
url: Troubleshooting errors during synchronization - https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/tshoot-connect-sync-errors
#>
<#
.SYNOPSIS
    Exports objects with synchronization errors.
.DESCRIPTION
    Reads onPremisesProvisioningErrors on users, groups and org contacts. The operations guide says to
    clean up errors that have been unresolved for more than 100 days; filter on DaysInError.
.EXAMPLE
    .\Get-SyncErrors.ps1 -Environment Global
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

function Get-Errors {
    param([Parameter(ValueFromPipeline)]$Object, [string]$ObjectType)
    process {
        $o = $Object
        $o.onPremisesProvisioningErrors | Where-Object { $_ } |
            Select-Object @{ n = "ObjectType"; e = { $ObjectType } }, @{ n = "Id"; e = { $o.id } }, @{ n = "DisplayName"; e = { $o.displayName } },
                @{ n = "UserPrincipalName"; e = { $o.userPrincipalName } }, category, propertyCausingError, value, occurredDateTime,
                @{ n = "DaysInError"; e = { if ($_.occurredDateTime) { [int]((Get-Date) - [datetime]$_.occurredDateTime).TotalDays } } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "Group.Read.All", "OrgContact.Read.All", "Directory.Read.All"

$file = Join-Path $Path "entra_sync_errors.csv"
Write-Host "Reading users, groups and contacts"
@(
    "$script:Graph/users?`$filter=onPremisesSyncEnabled eq true&`$select=id,displayName,userPrincipalName,onPremisesProvisioningErrors&`$count=true" | Get-GraphPage -Eventual | Get-Errors -ObjectType User
    "$script:Graph/groups?`$filter=onPremisesSyncEnabled eq true&`$select=id,displayName,onPremisesProvisioningErrors&`$count=true" | Get-GraphPage -Eventual | Get-Errors -ObjectType Group
    "$script:Graph/contacts?`$select=id,displayName,onPremisesProvisioningErrors" | Get-GraphPage | Get-Errors -ObjectType Contact
) | Sort-Object DaysInError -Descending | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
