<#PSScriptInfo
.VERSION 2026.10
.GUID 6ac61e10-a45b-470f-bec3-fcd613d7cbc4
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
Looks up the Entra tenant behind an email address or domain: tenant ID, name, default domain, namespace type, and whether it is a viral (unmanaged) tenant.
url: findTenantInformationByDomainName - https://learn.microsoft.com/en-us/graph/api/tenantrelationship-findtenantinformationbydomainname?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Looks up tenant details for email addresses or domains.
.DESCRIPTION
    Replaces Tenant\istenantviral and Tenant\lookup-tenant. Accepts pipeline input, so a CSV column of
    addresses can be piped in.
.EXAMPLE
    .\Get-TenantLookup.ps1 -Environment Global -Address "<person UPN>"
.EXAMPLE
    Import-Csv .\guests.csv | Select-Object -ExpandProperty mail | .\Get-TenantLookup.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Address
)

begin {
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

    function Get-TenantInfo {
        param([Parameter(ValueFromPipeline)][string]$Item)
        process {
            $domain = ($Item -split "@")[-1]
            $mail = if ($Item -like "*@*") { $Item } else { "user@$Item" }
            $realm = try { Invoke-RestMethod -Uri "$loginEndpoint/common/userrealm/?user=$([uri]::EscapeDataString($mail))&api-version=2.1" -ErrorAction Stop } catch { $null }
            $tenant = try { Invoke-MgGraphRequest -Uri "$script:Graph/tenantRelationships/findTenantInformationByDomainName(domainName='$domain')" -OutputType PSObject -ErrorAction Stop } catch { $null }
            $Item | Select-Object @{ n = "Address"; e = { $_ } },
                @{ n = "Domain"; e = { $domain } },
                @{ n = "TenantId"; e = { $tenant.tenantId } },
                @{ n = "TenantName"; e = { $tenant.displayName } },
                @{ n = "DefaultDomain"; e = { $tenant.defaultDomainName } },
                @{ n = "NameSpaceType"; e = { $realm.NameSpaceType } },
                @{ n = "FederationBrand"; e = { $realm.FederationBrandName } },
                @{ n = "CloudInstance"; e = { $realm.CloudInstanceName } },
                @{ n = "IsViral"; e = { [bool]($realm.IsViral -eq $true -or $realm.IsViral -eq "True") } }
        }
    }

    Connect-Cloud -Scopes "CrossTenantInformation.ReadBasic.All"
    $loginEndpoint = (Get-MgEnvironment -Name $script:Environment).AzureADEndpoint
}
process {
    $Address | Get-TenantInfo
}
