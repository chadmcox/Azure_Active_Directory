<#PSScriptInfo
.VERSION 2026.10
.GUID d0bda2e0-b8b5-4530-a63c-b3bca76da3b0
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
Lists every access review and shows what still has no regular review: guests, privileged roles, groups used in Conditional Access exclusions, and apps that require assignment, as the operations guide recommends.
url: Microsoft Entra ID Governance operations reference guide - https://learn.microsoft.com/en-us/entra/architecture/ops-guide-govern
url: List accessReviewScheduleDefinitions - https://learn.microsoft.com/en-us/graph/api/accessreviewset-list-definitions?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports access reviews and the gaps in review coverage.
.DESCRIPTION
    Writes two files: every access review definition (what it reviews, how often, its status), and a
    coverage list with one row per thing the guide says to review and whether a review covers it.
    Access reviews need Microsoft Entra ID P2 or ID Governance.
.EXAMPLE
    .\Get-AccessReviewCoverage.ps1 -Environment Global
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

function Get-ScopeText {
    param($Definition)
    @($Definition.scope.query; $Definition.scope.principalScopes.query; $Definition.scope.resourceScopes.query; $Definition.instanceEnumerationScope.query) -join " "
}

function Test-Covered {
    param([Parameter(ValueFromPipeline)]$Item)
    process {
        $i = $Item
        $match = @($definitions | Where-Object { (Get-ScopeText -Definition $_) -match [regex]::Escape($i.Pattern) })
        $i | Select-Object Area, Name, Id,
            @{ n = "Covered"; e = { [bool]$match } },
            @{ n = "Reviews"; e = { $match.displayName -join ";" } }
    }
}

Connect-Cloud -Scopes "AccessReview.Read.All", "Policy.Read.All", "Application.Read.All", "RoleManagement.Read.Directory"

$definitions = @(try { "$script:Graph/identityGovernance/accessReviews/definitions" | Get-GraphPage } catch { Write-Warning "Access reviews: $($_.Exception.Message)" })
$definitions | Select-Object displayName, status, createdDateTime,
    @{ n = "Scope"; e = { Get-ScopeText -Definition $_ } },
    @{ n = "Recurrence"; e = { "$($_.settings.recurrence.pattern.type) every $($_.settings.recurrence.pattern.interval)" } },
    @{ n = "AutoApply"; e = { $_.settings.autoApplyDecisionsEnabled } },
    @{ n = "DefaultDecision"; e = { $_.settings.defaultDecision } } |
    Export-Csv (Join-Path $Path "entra_access_reviews.csv") -NoTypeInformation

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
$caGroups = @("$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage | ForEach-Object { $_.conditions.users.excludeGroups } | Where-Object { $_ } | Select-Object -Unique)
$file = Join-Path $Path "entra_access_review_coverage.csv"
@(
    "Guests" | Select-Object @{ n = "Area"; e = { "External identities" } }, @{ n = "Name"; e = { "Guest users" } }, @{ n = "Id"; e = { $null } }, @{ n = "Pattern"; e = { "userType eq 'Guest'" } }
    "Roles" | Select-Object @{ n = "Area"; e = { "Privileged roles" } }, @{ n = "Name"; e = { "Directory roles" } }, @{ n = "Id"; e = { $null } }, @{ n = "Pattern"; e = { "roleManagement" } }
    $caGroups | ForEach-Object {
        $g = try { Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($_)?`$select=id,displayName" -OutputType PSObject -ErrorAction Stop } catch { $null }
        $_ | Select-Object @{ n = "Area"; e = { "Conditional Access exclusion group" } }, @{ n = "Name"; e = { $g.displayName } }, @{ n = "Id"; e = { $_ } }, @{ n = "Pattern"; e = { $_ } }
    }
    "$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$select=id,displayName,appOwnerOrganizationId,appRoleAssignmentRequired" | Get-GraphPage |
        Where-Object { $_.appRoleAssignmentRequired -and $_.appOwnerOrganizationId -ne $microsoftTenantId -and $_.'@odata.type' -notmatch 'agent' } |
        Select-Object @{ n = "Area"; e = { "Application" } }, @{ n = "Name"; e = { $_.displayName } }, @{ n = "Id"; e = { $_.id } }, @{ n = "Pattern"; e = { $_.id } }
) | Test-Covered | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file and $(Join-Path $Path 'entra_access_reviews.csv')"
