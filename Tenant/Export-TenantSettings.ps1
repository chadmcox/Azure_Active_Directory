<#PSScriptInfo
.VERSION 2026.10
.GUID 4c8c9db4-3b33-43d5-b0ed-d7cc36da5288
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
Backs up the main tenant-wide settings to JSON (organization, authorization policy, sync features, authentication methods, admin consent, staged rollout, cross-tenant defaults, security defaults) and licenses to CSV.
url: authorizationPolicy resource type - https://learn.microsoft.com/en-us/graph/api/resources/authorizationpolicy?view=graph-rest-beta
url: onPremisesDirectorySynchronization resource type - https://learn.microsoft.com/en-us/graph/api/resources/onpremisesdirectorysynchronization?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports tenant settings and licenses.
.DESCRIPTION
    Replaces getAADSettings (MSOnline) and Backup\export-Settings.
.EXAMPLE
    .\Export-TenantSettings.ps1 -Environment Global
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

function Export-Setting {
    param([Parameter(ValueFromPipeline)][string]$Name)
    process {
        Write-Host "  $Name"
        $data = try { "$script:Graph/$($settings[$Name])" | Get-GraphPage } catch { Write-Warning "$($Name): $($_.Exception.Message)"; return }
        $data | ConvertTo-Json -Depth 20 | Out-File (Join-Path $folder "$Name.json")
    }
}

Connect-Cloud -Scopes "Organization.Read.All", "Policy.Read.All", "OnPremDirectorySynchronization.Read.All", "Directory.Read.All"

$settings = [ordered]@{
    organization                  = "organization"
    authorizationPolicy           = "policies/authorizationPolicy"
    securityDefaults              = "policies/identitySecurityDefaultsEnforcementPolicy"
    onPremisesSynchronization     = "directory/onPremisesSynchronization"
    authenticationMethodsPolicy   = "policies/authenticationMethodsPolicy"
    authenticationStrengths       = "policies/authenticationStrengthPolicies"
    adminConsentRequestPolicy     = "policies/adminConsentRequestPolicy"
    permissionGrantPolicies       = "policies/permissionGrantPolicies"
    featureRolloutPolicies        = "policies/featureRolloutPolicies"
    crossTenantAccessDefault      = "policies/crossTenantAccessPolicy/default"
    crossTenantAccessPartners     = "policies/crossTenantAccessPolicy/partners"
    externalIdentitiesPolicy      = "policies/externalIdentitiesPolicy"
    groupSettings                 = "groupSettings"
    domains                       = "domains"
}

$folder = New-Item -ItemType Directory -Path (Join-Path $Path "Tenant_Settings_$(Get-Date -Format yyyy-MM-dd)") -Force
Write-Host "Exporting settings"
$settings.Keys | Export-Setting

"$script:Graph/subscribedSkus" | Get-GraphPage |
    Select-Object skuPartNumber, skuId, capabilityStatus, consumedUnits,
        @{ n = "Enabled"; e = { $_.prepaidUnits.enabled } },
        @{ n = "Suspended"; e = { $_.prepaidUnits.suspended } },
        @{ n = "Warning"; e = { $_.prepaidUnits.warning } } |
    Export-Csv (Join-Path $folder "licenses.csv") -NoTypeInformation
Write-Host "Results: $folder"
