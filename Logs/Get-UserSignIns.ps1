<#PSScriptInfo
.VERSION 2026.10
.GUID bc195997-22f5-45f5-9334-896a11c496cf
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
Pulls sign-in logs for one user or for everyone, including the Conditional Access policies that applied, for troubleshooting.
url: List signIns - https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta
url: Sign-in error codes - https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes
#>
<#
.SYNOPSIS
    Exports sign-ins for a user or for everyone.
.DESCRIPTION
    Replaces viewAADUserSignins and viewAADUserSigninwithCAP. Interactive sign-ins only; for non-interactive sign-ins use Get-UserNonInteractiveSignIns.ps1, for account lockouts Get-LockedOutAccounts.ps1.
.PARAMETER UserPrincipalName
    Only this user's sign-ins.
.EXAMPLE
    .\Get-UserSignIns.ps1 -Environment Global -UserPrincipalName "<person UPN>" -Days 3
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$UserPrincipalName,
    [int]$Days = 7,
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

Connect-Cloud -Scopes "AuditLog.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$filters = @(
    "createdDateTime ge $since"
    if ($UserPrincipalName) { "userPrincipalName eq '$UserPrincipalName'" }
)
$file = Join-Path $Path "entra_signins.csv"
"$script:Graph/auditLogs/signIns?`$filter=$($filters -join ' and ')" | Get-GraphPage |
    Select-Object createdDateTime, userPrincipalName, appDisplayName, resourceDisplayName, clientAppUsed, ipAddress,
        @{ n = "Location"; e = { "$($_.location.city), $($_.location.state), $($_.location.countryOrRegion)" } },
        @{ n = "ErrorCode"; e = { $_.status.errorCode } },
        @{ n = "FailureReason"; e = { $_.status.failureReason } },
        @{ n = "Device"; e = { $_.deviceDetail.displayName } },
        @{ n = "OperatingSystem"; e = { $_.deviceDetail.operatingSystem } },
        @{ n = "Browser"; e = { $_.deviceDetail.browser } },
        @{ n = "TrustType"; e = { $_.deviceDetail.trustType } },
        @{ n = "Compliant"; e = { $_.deviceDetail.isCompliant } },
        authenticationRequirement, conditionalAccessStatus, riskLevelDuringSignIn,
        @{ n = "AppliedPolicies"; e = { ($_.appliedConditionalAccessPolicies | Where-Object { $_.result -in "success", "failure" } | ForEach-Object { "$($_.displayName) ($($_.result))" }) -join ";" } },
        correlationId |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
