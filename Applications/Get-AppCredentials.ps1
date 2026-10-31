<#PSScriptInfo
.VERSION 2026.10
.GUID 39ef7e29-3d11-4c74-879e-335289f9d212
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
Reports every certificate and client secret on app registrations and service principals, with expiry, lifetime and whether it is long-lived.
url: Application keyCredentials and passwordCredentials - https://learn.microsoft.com/en-us/graph/api/resources/application?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports all app and service principal credentials.
.DESCRIPTION
    Replaces get-AllAppCredentials and createAADAPPandSPCredentialReport. Managed identities and
    signing certificates (usage Sign) are left out unless -IncludeAll is used.
.PARAMETER ExpiringInDays
    Flags credentials that expire within this many days. Default 30.
.EXAMPLE
    .\Get-AppCredentials.ps1 -Environment Global -ExpiringInDays 60
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$ExpiringInDays = 30,
    [switch]$IncludeAll,
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

function Get-Credentials {
    param([Parameter(ValueFromPipeline)]$Object)
    process {
        $owner = $Object
        @(
            $owner.keyCredentials | Select-Object *, @{ n = "CredentialType"; e = { "Certificate" } }
            $owner.passwordCredentials | Select-Object *, @{ n = "CredentialType"; e = { "Secret" } }
        ) | Where-Object { $_ } | Select-Object @{ n = "ObjectType"; e = { $owner.ObjectType } },
            @{ n = "DisplayName"; e = { $owner.displayName } },
            @{ n = "AppId"; e = { $owner.appId } },
            @{ n = "ObjectId"; e = { $owner.id } },
            @{ n = "ServicePrincipalType"; e = { $owner.servicePrincipalType } },
            @{ n = "Publisher"; e = { $owner.publisherName } },
            CredentialType,
            @{ n = "CredentialName"; e = { $_.displayName } },
            keyId, type, usage, startDateTime, endDateTime,
            @{ n = "Expired"; e = { [datetime]$_.endDateTime -lt (Get-Date) } },
            @{ n = "ExpiresSoon"; e = { [datetime]$_.endDateTime -ge (Get-Date) -and [datetime]$_.endDateTime -lt (Get-Date).AddDays($ExpiringInDays) } },
            @{ n = "LifetimeDays"; e = { [int]([datetime]$_.endDateTime - [datetime]$_.startDateTime).TotalDays } },
            @{ n = "LongLived"; e = { ([datetime]$_.endDateTime - [datetime]$_.startDateTime).TotalDays -gt 366 } }
    }
}

Connect-Cloud -Scopes "Application.Read.All"

$file = Join-Path $Path "entra_app_credentials.csv"
Write-Host "Getting app registrations and service principals"
@(
    "$script:Graph/applications?`$select=id,appId,displayName,keyCredentials,passwordCredentials" | Get-GraphPage |
        Select-Object *, @{ n = "ObjectType"; e = { "Application" } }
    "$script:Graph/servicePrincipals?`$select=id,appId,displayName,servicePrincipalType,publisherName,keyCredentials,passwordCredentials" | Get-GraphPage |
        Select-Object *, @{ n = "ObjectType"; e = { "ServicePrincipal" } }
) | Get-Credentials |
    Where-Object { $IncludeAll -or ($_.ServicePrincipalType -ne "ManagedIdentity" -and $_.usage -ne "Sign") } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
