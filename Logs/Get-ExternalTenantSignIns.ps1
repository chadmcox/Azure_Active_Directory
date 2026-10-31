<#PSScriptInfo
.VERSION 2026.10
.GUID 1334e306-2bf8-4543-87fe-89b696071f7d
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
Lists the other tenants your users sign in to (as guests or through cross-tenant access), with the tenant name and the apps used.
url: Cross-tenant access activity workbook - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/workbook-cross-tenant-access-activity
url: findTenantInformationByTenantId - https://learn.microsoft.com/en-us/graph/api/tenantrelationship-findtenantinformationbytenantid?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Summarizes sign-ins by your users into external tenants.
.DESCRIPTION
    Replaces Users\retrieve-ExternalTenantsUsedByUsers.
.EXAMPLE
    .\Get-ExternalTenantSignIns.ps1 -Environment Global -Days 10
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 10,
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

function Get-TenantName {
    param([string]$TenantId)
    if (-not $tenantNames.ContainsKey($TenantId)) {
        $tenantNames[$TenantId] = try {
            (Invoke-MgGraphRequest -Uri "$script:Graph/tenantRelationships/findTenantInformationByTenantId(tenantId='$TenantId')" -OutputType PSObject -ErrorAction Stop).displayName
        } catch { "unknown" }
    }
    $tenantNames[$TenantId]
}

Connect-Cloud -Scopes "AuditLog.Read.All", "CrossTenantInformation.ReadBasic.All"

$tenantNames = @{}
$homeTenant = (Get-MgContext).TenantId
$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_external_tenant_signins.csv"
"$script:Graph/auditLogs/signIns?`$filter=createdDateTime ge $since and resourceTenantId ne '$homeTenant' and status/errorCode eq 0" | Get-GraphPage |
    Where-Object { $_.userType -ne "guest" -and $_.homeTenantId -eq $homeTenant } |
    Group-Object resourceTenantId, appDisplayName |
    Select-Object @{ n = "TenantId"; e = { $_.Group[0].resourceTenantId } },
        @{ n = "TenantName"; e = { Get-TenantName -TenantId $_.Group[0].resourceTenantId } },
        @{ n = "App"; e = { $_.Group[0].appDisplayName } },
        @{ n = "SignIns"; e = { $_.Count } },
        @{ n = "Users"; e = { @($_.Group.userPrincipalName | Sort-Object -Unique).Count } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
