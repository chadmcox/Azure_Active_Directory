<#PSScriptInfo
.VERSION 2026.10
.GUID cf30ff54-dfcb-49c0-b014-3ff0bb300a57
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
Lists every entitlement management catalog and access package with its assignment policies (who can request, whether approval is required, how long access lasts, whether access reviews run) and how many active assignments it has.
url: What is entitlement management - https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-overview
url: List accessPackages - https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-list-accesspackages?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports access packages and their policies.
.DESCRIPTION
    One row per access package policy. Access packages with no expiration or no access review, or
    policies that let anyone request without approval, are worth reviewing. Needs Microsoft Entra ID P2
    or ID Governance.
.EXAMPLE
    .\Get-AccessPackages.ps1 -Environment Global
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

function Format-Package {
    param([Parameter(ValueFromPipeline)]$Package)
    process {
        $p = $Package
        $active = @("$script:Graph/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq '$($p.id)' and state eq 'Delivered'&`$select=id" | Get-GraphPage).Count
        @($p.assignmentPolicies) | ForEach-Object {
            $policy = $_
            $p | Select-Object @{ n = "Catalog"; e = { $p.catalog.displayName } }, @{ n = "AccessPackage"; e = { $p.displayName } }, @{ n = "AccessPackageId"; e = { $p.id } },
                isHidden, @{ n = "ActiveAssignments"; e = { $active } },
                @{ n = "Policy"; e = { $policy.displayName } },
                @{ n = "WhoCanRequest"; e = { $policy.allowedTargetScope } },
                @{ n = "ApprovalRequired"; e = { [bool]$policy.requestApprovalSettings.isApprovalRequiredForAdd } },
                @{ n = "Expiration"; e = { if ($policy.expiration.type -eq "noExpiration") { "Never" } else { "$($policy.expiration.type) $($policy.expiration.duration)" } } },
                @{ n = "AccessReviews"; e = { [bool]$policy.reviewSettings.isEnabled } },
                @{ n = "Finding"; e = {
                    @(
                        if ($policy.expiration.type -eq "noExpiration") { "No expiration" }
                        if (-not $policy.reviewSettings.isEnabled) { "No access review" }
                        if (-not $policy.requestApprovalSettings.isApprovalRequiredForAdd -and $policy.allowedTargetScope -match "allMemberUsers|allDirectoryUsers|allExternalUsers|allConfiguredConnectedOrganizationUsers") { "Broad requests without approval" }
                    ) -join ";" } }
        }
    }
}

Connect-Cloud -Scopes "EntitlementManagement.Read.All"

$file = Join-Path $Path "entra_access_packages.csv"
@(try { "$script:Graph/identityGovernance/entitlementManagement/accessPackages?`$expand=catalog,assignmentPolicies" | Get-GraphPage } catch { Write-Warning "Entitlement management: $($_.Exception.Message)" }) |
    Format-Package | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
