<#PSScriptInfo
.VERSION 2026.10
.GUID 1218edb4-8a94-468d-a40f-69b873288bb9
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
Inventories every enabled enterprise app with its sign-in type (SAML, OIDC, password, desktop, app proxy, OAuth2), last sign-in, 30-day sign-in count, owners and whether Entra recommends removing it as unused.
url: servicePrincipalSignInActivity - https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipalsigninactivity?view=graph-rest-beta
url: Remove unused applications recommendation - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/recommendation-remove-unused-apps
#>
<#
.SYNOPSIS
    Exports an inventory of enterprise apps with activity, type and owners.
.DESCRIPTION
    Replaces get-EntraApplicationsDetails, get-SPSignInActivity, get-EntraDesktopApplication,
    get-EntraSAMLApplications, get-StaleAppsfromEntra, get-StaleAppFromRecommendation and
    Backup\export-ServicePrincipals. Filter the CSV on Type, DaysSinceLastSignIn or EntraRecommendsRemoval.
.PARAMETER IncludeMicrosoftApps
    Include Microsoft first-party apps. They are left out by default.
.EXAMPLE
    .\Get-AppInventory.ps1 -Environment Global
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

function Get-LastSignIns {
    "$script:Graph/reports/servicePrincipalSignInActivities" | Get-GraphPage |
        Where-Object { $_.lastSignInActivity.lastSignInDateTime } |
        Select-Object appId,
            @{ n = "LastSignInDateTime"; e = { $_.lastSignInActivity.lastSignInDateTime } },
            @{ n = "SignInActivityType"; e = {
                if ($_.delegatedClientSignInActivity.lastSignInDateTime) { "delegatedClient" }
                elseif ($_.delegatedResourceSignInActivity.lastSignInDateTime) { "delegatedResource" }
                elseif ($_.applicationAuthenticationClientSignInActivity.lastSignInDateTime) { "applicationAuthenticationClient" }
                elseif ($_.applicationAuthenticationResourceSignInActivity.lastSignInDateTime) { "applicationAuthenticationResource" }
                else { "unknown" } } }
}

function Get-UnusedAppRecommendations {
    "$script:Graph/directory/recommendations" | Get-GraphPage |
        Where-Object { $_.status -eq "active" -and $_.displayName -eq "Remove unused applications" } |
        ForEach-Object { "$script:Graph/directory/recommendations/$($_.id)/impactedResources" | Get-GraphPage } |
        Where-Object { $_.status -eq "active" } |
        Select-Object id, addedDateTime
}

function Get-AppType {
    param($ServicePrincipal)
    if ($ServicePrincipal.preferredSingleSignOnMode -in "saml", "oidc", "password") { return $ServicePrincipal.preferredSingleSignOnMode }
    if ($ServicePrincipal.replyUrls -contains "urn:ietf:wg:oauth:2.0:oob") { return "desktop" }
    if ($ServicePrincipal.tags -contains "WindowsAzureActiveDirectoryOnPremApp") { return "app-proxy" }
    if ($openIdClients.ContainsKey($ServicePrincipal.id)) { return "oidc" }
    $app = $applications[$ServicePrincipal.appId]
    if ($app -and $app.web.redirectUris -and ($app.web.implicitGrantSettings.enableIdTokenIssuance -or $app.web.implicitGrantSettings.enableAccessTokenIssuance)) { return "oauth2" }
    "unknown"
}

function Format-App {
    param([Parameter(ValueFromPipeline)]$ServicePrincipal)
    process {
        $lastSignIn = $lastSignIns[$ServicePrincipal.appId]
        $ServicePrincipal | Select-Object @{ n = "Type"; e = { Get-AppType -ServicePrincipal $_ } },
            id, appId, displayName, publisherName, accountEnabled, appRoleAssignmentRequired, preferredSingleSignOnMode, signInAudience, createdDateTime,
            @{ n = "LastSignInDateTime"; e = { $lastSignIn.LastSignInDateTime } },
            @{ n = "DaysSinceLastSignIn"; e = { if ($lastSignIn) { [int]((Get-Date) - [datetime]$lastSignIn.LastSignInDateTime).TotalDays } } },
            @{ n = "SignInActivityType"; e = { $lastSignIn.SignInActivityType } },
            @{ n = "SuccessfulSignIns30Days"; e = { $signInCounts[$_.appId].successfulSignInCount } },
            @{ n = "EntraRecommendsRemoval"; e = { $unusedApps[$_.appId].addedDateTime } },
            @{ n = "AzureAppService"; e = { $_.tags -contains "AppServiceIntegratedApp" } },
            @{ n = "ReplyUrls"; e = { $_.replyUrls -join ";" } },
            @{ n = "Tags"; e = { $_.tags -join ";" } },
            @{ n = "NotificationEmailAddresses"; e = { $_.notificationEmailAddresses -join ";" } },
            @{ n = "Owners"; e = { ($_.owners | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "Directory.Read.All", "AuditLog.Read.All", "Reports.Read.All", "DirectoryRecommendations.Read.All"

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"

Write-Host "Getting service principal sign-in activity"
$lastSignIns = @(Get-LastSignIns) | Group-Object appId -AsHashTable -AsString
if (-not $lastSignIns) { $lastSignIns = @{} }
Write-Host "Getting Entra recommendations for unused apps"
$unusedApps = @(Get-UnusedAppRecommendations) | Group-Object id -AsHashTable -AsString
if (-not $unusedApps) { $unusedApps = @{} }
Write-Host "Getting 30 day sign-in summary"
$signInCounts = @("$script:Graph/reports/getAzureADApplicationSignInSummary(period='D30')" | Get-GraphPage) | Group-Object id -AsHashTable -AsString
if (-not $signInCounts) { $signInCounts = @{} }
Write-Host "Getting app registrations"
$applications = @("$script:Graph/applications?`$select=appId,web" | Get-GraphPage) | Group-Object appId -AsHashTable -AsString
if (-not $applications) { $applications = @{} }
Write-Host "Getting apps with openid consent"
$openIdClients = @("$script:Graph/oauth2PermissionGrants?`$top=999" | Get-GraphPage | Where-Object { $_.scope -match "\bopenid\b" }) | Group-Object clientId -AsHashTable -AsString
if (-not $openIdClients) { $openIdClients = @{} }

$file = Join-Path $Path "entra_app_inventory.csv"
Write-Host "Getting enabled enterprise apps and building report"
"$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage |
    Where-Object { ($IncludeMicrosoftApps -or $_.appOwnerOrganizationId -ne $microsoftTenantId) -and $_.'@odata.type' -notmatch 'agent' } |
    Format-App | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
