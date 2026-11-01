<#PSScriptInfo
.VERSION 2026.10
.GUID 2f58cd35-a19a-4558-bb0b-521e9013ce98
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
Reports every application and delegated permission granted to apps for retiring Azure AD Graph API access (any permission on Azure AD Graph), with the app's owners.
url: List appRoleAssignedTo - https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignedto?view=graph-rest-beta
url: List oauth2PermissionGrants - https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports apps with retiring Azure AD Graph API permissions.
.DESCRIPTION
    Replaces get-AADGraphApps, get-ADGraphApplications, get-AzureADGraphPerms and get-AzureADGraphDelegatedPerms. Move these apps to Microsoft Graph.
.PARAMETER IncludeMicrosoftApps
    Include Microsoft first-party apps. They are left out by default.
.EXAMPLE
    .\Get-AppAzureADGraphPermissions.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$IncludeMicrosoftApps,
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

function Get-ServicePrincipals {
    "$script:Graph/servicePrincipals?`$select=id,appId,displayName,publisherName,appOwnerOrganizationId,servicePrincipalType,accountEnabled,appRoles&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage
}

function Get-ApplicationPermissions {
    param([Parameter(ValueFromPipeline)]$Resource)
    process {
        if (-not ($Resource.appRoles | Where-Object { $_.allowedMemberTypes -contains "Application" })) { return }
        $roles = $Resource.appRoles | Group-Object id -AsHashTable -AsString
        "$script:Graph/servicePrincipals/$($Resource.id)/appRoleAssignedTo" | Get-GraphPage |
            Where-Object { $_.principalType -eq "ServicePrincipal" } |
            Select-Object @{ n = "PermissionType"; e = { "Application" } },
                @{ n = "Permission"; e = { $roles[$_.appRoleId].value } },
                @{ n = "API"; e = { $Resource.displayName } },
                @{ n = "APIAppId"; e = { $Resource.appId } },
                @{ n = "ConsentType"; e = { "AllPrincipals" } },
                @{ n = "ConsentedUserId"; e = { $null } },
                @{ n = "PrincipalId"; e = { $_.principalId } }
    }
}

function Get-DelegatedPermissions {
    "$script:Graph/oauth2PermissionGrants" | Get-GraphPage | ForEach-Object {
        $grant = $_
        $grant.scope -split " " | Where-Object { $_ } |
            Select-Object @{ n = "PermissionType"; e = { "Delegated" } },
                @{ n = "Permission"; e = { $_ } },
                @{ n = "API"; e = { $spById[$grant.resourceId].displayName } },
                @{ n = "APIAppId"; e = { $spById[$grant.resourceId].appId } },
                @{ n = "ConsentType"; e = { $grant.consentType } },
                @{ n = "ConsentedUserId"; e = { $grant.principalId } },
                @{ n = "PrincipalId"; e = { $grant.clientId } }
    }
}

function Select-AadGraphPermission {
    param([Parameter(ValueFromPipeline)]$Permission)
    process {
        if ($Permission.APIAppId -eq "00000002-0000-0000-c000-000000000000") { $Permission }
    }
}

function Add-AppDetails {
    param([Parameter(ValueFromPipeline)]$Permission)
    process {
        $app = $spById[$Permission.PrincipalId]
        $Permission | Select-Object PermissionType, Permission, API, APIAppId, ConsentType, ConsentedUserId,
            @{ n = "App"; e = { $app.displayName } },
            @{ n = "AppId"; e = { $app.appId } },
            @{ n = "AppObjectId"; e = { $app.id } },
            @{ n = "Publisher"; e = { $app.publisherName } },
            @{ n = "ServicePrincipalType"; e = { $app.servicePrincipalType } },
            @{ n = "Enabled"; e = { $app.accountEnabled } },
            @{ n = "Owners"; e = { ($app.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "MicrosoftApp"; e = { $app.appOwnerOrganizationId -eq $microsoftTenantId } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "Directory.Read.All"

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
Write-Host "Getting service principals"
$servicePrincipals = Get-ServicePrincipals
$spById = $servicePrincipals | Group-Object id -AsHashTable -AsString

$file = Join-Path $Path "entra_app_azureadgraphpermissions.csv"
Write-Host "Building report"
@(
    $servicePrincipals | Get-ApplicationPermissions
    Get-DelegatedPermissions
) | Select-AadGraphPermission | Add-AppDetails |
    Where-Object { $IncludeMicrosoftApps -or -not $_.MicrosoftApp } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
