<#PSScriptInfo
.VERSION 2026.10
.GUID e7ad1315-b99a-4af9-836a-034d850f7e42
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
Writes the object IDs of every user who holds a privileged directory role (active or eligible) as a quoted, comma-separated list to paste into a KQL query in Log Analytics or Sentinel.
url: List roleAssignments - https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignments?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a KQL-ready list of privileged admin object IDs.
.DESCRIPTION
    Replaces PIM\RetrieveAdminsforKQL and the -KqlList switch that was on Get-RoleMembers.ps1.
    Group-based assignments are expanded to their members.
.EXAMPLE
    .\Get-AdminIdsForKql.ps1 -Environment Global
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

function Get-UserIds {
    param([Parameter(ValueFromPipeline)]$Assignment)
    process {
        if ($Assignment.principal.'@odata.type' -eq "#microsoft.graph.user") { $Assignment.principalId }
        elseif ($Assignment.principal.'@odata.type' -eq "#microsoft.graph.group") {
            "$script:Graph/groups/$($Assignment.principalId)/transitiveMembers/microsoft.graph.user?`$select=id" | Get-GraphPage | Select-Object -ExpandProperty id
        }
    }
}

Connect-Cloud -Scopes "RoleManagement.Read.Directory", "Directory.Read.All"

$privileged = "$script:Graph/roleManagement/directory/roleDefinitions?`$filter=isPrivileged eq true&`$select=id" | Get-GraphPage | Select-Object -ExpandProperty id
$ids = @(
    "$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal" | Get-GraphPage
    try { "$script:Graph/roleManagement/directory/roleEligibilitySchedules?`$expand=principal" | Get-GraphPage } catch { Write-Warning "Eligible assignments are not available (needs Microsoft Entra ID P2)" }
) | Where-Object { $_.roleDefinitionId -in $privileged } | Get-UserIds | Sort-Object -Unique

$file = Join-Path $Path "entra_admin_ids_for_kql.txt"
'"' + ($ids -join '","') + '"' | Out-File $file
Write-Host "$($ids.Count) admins. Results: $file"
