<#PSScriptInfo
.VERSION 2026.10
.GUID 237e2bde-81d7-456a-b92f-f2a0ca694fbb
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
Lists every application published through Microsoft Entra application proxy with its external and internal URL, pre-authentication type, connector group and single sign-on mode, and flags apps that use passthrough (no Entra pre-authentication).
url: Remote access to on-premises apps through application proxy - https://learn.microsoft.com/en-us/entra/identity/app-proxy/overview-what-is-app-proxy
#>
<#
.SYNOPSIS
    Exports application proxy apps and their settings.
.DESCRIPTION
    Passthrough apps aren't protected by Conditional Access or MFA, so review each one.
.EXAMPLE
    .\Get-AppProxyApps.ps1 -Environment Global
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

function Format-ProxyApp {
    param([Parameter(ValueFromPipeline)]$ServicePrincipal)
    process {
        $sp = $ServicePrincipal
        $app = try { Invoke-MgGraphRequest -Uri "$script:Graph/applications(appId='$($sp.appId)')?`$select=id,onPremisesPublishing" -OutputType PSObject -ErrorAction Stop } catch { return }
        $group = try { Invoke-MgGraphRequest -Uri "$script:Graph/applications/$($app.id)/connectorGroup" -OutputType PSObject -ErrorAction Stop } catch { $null }
        $pub = $app.onPremisesPublishing
        $sp | Select-Object displayName, appId, accountEnabled, appRoleAssignmentRequired, preferredSingleSignOnMode,
            @{ n = "ExternalUrl"; e = { $pub.externalUrl } },
            @{ n = "InternalUrl"; e = { $pub.internalUrl } },
            @{ n = "PreAuthentication"; e = { $pub.externalAuthenticationType } },
            @{ n = "ConnectorGroup"; e = { $group.name } },
            @{ n = "TranslateUrls"; e = { $pub.isTranslateHostHeaderEnabled } },
            @{ n = "BackendCertValidation"; e = { $pub.isBackendCertificateValidationEnabled } },
            @{ n = "Finding"; e = { if ($pub.externalAuthenticationType -eq "passthru") { "Passthrough - no Entra pre-authentication" } elseif (-not $_.appRoleAssignmentRequired) { "Assignment not required" } } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "Directory.Read.All"

$file = Join-Path $Path "entra_app_proxy_apps.csv"
"$script:Graph/servicePrincipals?`$filter=tags/any(t:t eq 'WindowsAzureActiveDirectoryOnPremApp')&`$select=id,appId,displayName,accountEnabled,appRoleAssignmentRequired,preferredSingleSignOnMode" |
    Get-GraphPage | Format-ProxyApp | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
