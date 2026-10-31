<#PSScriptInfo
.VERSION 2026.10
.GUID e45ab48a-4f24-41b2-a9bb-0539a4faf30f
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
Lists the registered domains and every place each domain is used on users, deleted users, groups, contacts, app registrations and service principals, which is needed before a domain can be removed.
url: Manage custom domain names - https://learn.microsoft.com/en-us/entra/identity/users/domains-manage
#>
<#
.SYNOPSIS
    Exports registered domains and every object attribute that uses them.
.DESCRIPTION
    Replaces Custom Domain\inventory-everyobjectdomainattribute and Backup\export-RegisteredDomains.
    Use -Domain to only report one domain.
.EXAMPLE
    .\Get-DomainUsage.ps1 -Environment Global -Domain "<domain name>"
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$Domain,
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

function Expand-DomainAttributes {
    param([Parameter(ValueFromPipeline)]$Object, [string]$ObjectType, [string]$IdProperty, [string[]]$Attributes)
    process {
        $o = $Object
        $Attributes | ForEach-Object {
            $attribute = $_
            $o.$attribute | Where-Object { $_ } | Select-Object @{ n = "ObjectType"; e = { $ObjectType } },
                @{ n = "Identifier"; e = { $o.$IdProperty } },
                @{ n = "Attribute"; e = { $attribute } },
                @{ n = "Value"; e = { $_ } },
                @{ n = "Domain"; e = { (($_ -replace '^[a-zA-Z0-9]+:', '') -split '@' | Select-Object -Last 1) -replace '^https?://', '' -replace '/.*$', '' } }
        }
    }
}

Connect-Cloud -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All", "Application.Read.All", "Domain.Read.All"

$domainFile = Join-Path $Path "entra_registered_domains.csv"
"$script:Graph/domains" | Get-GraphPage |
    Select-Object id, authenticationType, isDefault, isInitial, isVerified, isRoot, isAdminManaged, @{ n = "supportedServices"; e = { $_.supportedServices -join ";" } } |
    Export-Csv $domainFile -NoTypeInformation

$file = Join-Path $Path "entra_domain_references.csv"
Write-Host "Reading users, groups, contacts and apps"
@(
    "$script:Graph/users?`$select=userPrincipalName,mail,otherMails,proxyAddresses,onPremisesUserPrincipalName" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType User -IdProperty userPrincipalName -Attributes userPrincipalName, mail, onPremisesUserPrincipalName, otherMails, proxyAddresses
    "$script:Graph/directory/deletedItems/microsoft.graph.user?`$select=userPrincipalName,mail,otherMails,proxyAddresses" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType DeletedUser -IdProperty userPrincipalName -Attributes userPrincipalName, mail, otherMails, proxyAddresses
    "$script:Graph/groups?`$select=displayName,mail,proxyAddresses" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType Group -IdProperty displayName -Attributes mail, proxyAddresses
    "$script:Graph/contacts?`$select=displayName,mail,proxyAddresses" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType OrgContact -IdProperty displayName -Attributes mail, proxyAddresses
    "$script:Graph/applications?`$select=displayName,identifierUris" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType Application -IdProperty displayName -Attributes identifierUris
    "$script:Graph/servicePrincipals?`$select=displayName,servicePrincipalNames" | Get-GraphPage |
        Expand-DomainAttributes -ObjectType ServicePrincipal -IdProperty displayName -Attributes servicePrincipalNames
) | Where-Object { $_.Domain -and (-not $Domain -or $_.Domain -eq $Domain -or $_.Domain -like "*.$Domain") } |
    Sort-Object Domain, ObjectType, Identifier, Attribute |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $domainFile and $file"
