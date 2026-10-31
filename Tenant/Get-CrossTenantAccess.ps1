<#PSScriptInfo
.VERSION 2026.10
.GUID 5dee0247-d09f-46ee-9c44-1f3a6ff9ebdb
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
Reports cross-tenant access settings for the default and for every partner organization: B2B collaboration and B2B direct connect inbound and outbound, which MFA and device claims are trusted, automatic invitation redemption, and cross-tenant sync.
url: Cross-tenant access overview - https://learn.microsoft.com/en-us/entra/external-id/cross-tenant-access-overview
url: List partners - https://learn.microsoft.com/en-us/graph/api/crosstenantaccesspolicy-list-partners?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports cross-tenant access settings.
.DESCRIPTION
    Empty values on a partner mean it inherits the default row.
.EXAMPLE
    .\Get-CrossTenantAccess.ps1 -Environment Global
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

function Format-Setting {
    param([Parameter(ValueFromPipeline)]$Setting, [string]$Name)
    process {
        $s = $Setting
        $s | Select-Object @{ n = "Partner"; e = { $Name } }, @{ n = "TenantId"; e = { $s.tenantId } },
            @{ n = "IsServiceProvider"; e = { $s.isServiceProvider } },
            @{ n = "B2BCollaborationInbound"; e = { $s.b2bCollaborationInbound.usersAndGroups.accessType } },
            @{ n = "B2BCollaborationOutbound"; e = { $s.b2bCollaborationOutbound.usersAndGroups.accessType } },
            @{ n = "B2BDirectConnectInbound"; e = { $s.b2bDirectConnectInbound.usersAndGroups.accessType } },
            @{ n = "B2BDirectConnectOutbound"; e = { $s.b2bDirectConnectOutbound.usersAndGroups.accessType } },
            @{ n = "TrustMfa"; e = { $s.inboundTrust.isMfaAccepted } },
            @{ n = "TrustCompliantDevice"; e = { $s.inboundTrust.isCompliantDeviceAccepted } },
            @{ n = "TrustHybridJoinedDevice"; e = { $s.inboundTrust.isHybridAzureADJoinedDeviceAccepted } },
            @{ n = "AutoRedeemInbound"; e = { $s.automaticUserConsentSettings.inboundAllowed } },
            @{ n = "AutoRedeemOutbound"; e = { $s.automaticUserConsentSettings.outboundAllowed } },
            @{ n = "CrossTenantSyncInbound"; e = {
                if ($s.tenantId) { $(try { Invoke-MgGraphRequest -Uri "$script:Graph/policies/crossTenantAccessPolicy/partners/$($s.tenantId)/identitySynchronization" -OutputType PSObject -ErrorAction Stop } catch { $null }).userSyncInbound.isSyncAllowed } } }
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "CrossTenantInformation.ReadBasic.All"

$file = Join-Path $Path "entra_cross_tenant_access.csv"
@(
    "$script:Graph/policies/crossTenantAccessPolicy/default" | Get-GraphPage | Format-Setting -Name "(default)"
    "$script:Graph/policies/crossTenantAccessPolicy/partners" | Get-GraphPage | ForEach-Object {
        $name = try { (Invoke-MgGraphRequest -Uri "$script:Graph/tenantRelationships/findTenantInformationByTenantId(tenantId='$($_.tenantId)')" -OutputType PSObject -ErrorAction Stop).displayName } catch { "unknown" }
        $_ | Format-Setting -Name $name
    }
) | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
