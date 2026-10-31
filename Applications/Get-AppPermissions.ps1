<#PSScriptInfo
.VERSION 2026.10
.GUID 918bd3e7-067a-4214-bb09-02b37bfa5932
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
Reports every application (app role) and delegated (OAuth2) permission granted to service principals, with optional filters for Exchange, SharePoint, Azure AD Graph and ReadWrite permissions.
url: List appRoleAssignedTo - https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignedto?view=graph-rest-beta
url: List oauth2PermissionGrants - https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports the application and delegated permissions granted to apps in Entra ID.
.DESCRIPTION
    Replaces the old get-AllAppAssignedPermissions, get-AllAppDelegatedPermissions, get-assignedEXOPerms,
    get-assignedSPOPerms, get-delegatedEXOPerms, get-delegatedSPOPerms, get-graphAssignedPermissions,
    get-AppWithEXOFullAccessPerm, get-ADGraphApplications, get-SPToMuchPerms, export-ApplicationConsents,
    export-ApplicationRoleAssignments and the createAAD*PermissionReport scripts.
.PARAMETER PermissionType
    All, Application (app roles) or Delegated (OAuth2 grants).
.PARAMETER Workload
    All, Exchange (mailbox permissions), SharePoint (sites and files), AzureADGraph (retiring API)
    ReadWrite (any write permission - check the Owners column, owners of these apps are sensitive)
    or HighRisk (the consent grants the operations guide says to review: mail access, user impersonation
    and any ReadWrite permission).
.PARAMETER IncludeMicrosoftApps
    Include Microsoft first-party apps. They are left out by default.
.EXAMPLE
    .\Get-AppPermissions.ps1 -Environment Global -Workload Exchange
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("All", "Application", "Delegated")][string]$PermissionType = "All",
    [ValidateSet("All", "Exchange", "SharePoint", "AzureADGraph", "ReadWrite", "HighRisk")][string]$Workload = "All",
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

function Select-Workload {
    param([Parameter(ValueFromPipeline)]$Permission)
    process {
        $keep = switch ($Workload) {
            "Exchange"     { $Permission.Permission -in $exchangePermissions }
            "SharePoint"   { $Permission.Permission -like "Sites.*" -or $Permission.Permission -like "Files.*" }
            "AzureADGraph" { $Permission.APIAppId -eq "00000002-0000-0000-c000-000000000000" }
            "ReadWrite"    { $Permission.Permission -match "ReadWrite|FullControl|full_access_as_app|Manage" }
            "HighRisk"     { $Permission.Permission -in $highRiskPermissions -or $Permission.Permission -match "ReadWrite|FullControl" }
            default        { $true }
        }
        if ($keep) { $Permission }
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
$exchangePermissions = "Mail.Read", "Mail.Read.Shared", "Mail.ReadBasic", "Mail.ReadBasic.All", "Mail.ReadWrite",
    "Mail.ReadWrite.Shared", "Mail.Send", "Mail.Send.Shared", "MailboxSettings.Read", "MailboxSettings.ReadWrite",
    "EWS.AccessAsUser.All", "Exchange.Manage", "full_access_as_app", "IMAP.AccessAsUser.All", "POP.AccessAsUser.All", "SMTP.Send"

# Permissions the operations guide says to scrutinize: mail access and full user impersonation.
$highRiskPermissions = "EAS.AccessAsUser.All", "EWS.AccessAsUser.All", "Mail.Read", "Mail.Read.Shared", "Mail.ReadWrite", "Mail.Send",
    "Directory.AccessAsUser.All", "user_impersonation", "full_access_as_app", "RoleManagement.ReadWrite.Directory", "AppRoleAssignment.ReadWrite.All"

Write-Host "Getting service principals"
$servicePrincipals = Get-ServicePrincipals
$spById = $servicePrincipals | Group-Object id -AsHashTable -AsString

$file = Join-Path $Path "entra_app_permissions_$Workload.csv"
Write-Host "Building report"
@(
    if ($PermissionType -in "All", "Application") { $servicePrincipals | Get-ApplicationPermissions }
    if ($PermissionType -in "All", "Delegated") { Get-DelegatedPermissions }
) | Select-Workload | Add-AppDetails |
    Where-Object { $IncludeMicrosoftApps -or -not $_.MicrosoftApp } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
