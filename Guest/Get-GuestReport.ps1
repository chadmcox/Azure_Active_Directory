<#PSScriptInfo
.VERSION 2026.10
.GUID 65dc4664-e5bd-4b68-995b-c1e19b818262
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
Reports every guest with invite state, last sign-in, sponsors and sign-in issuer, and can check whether each guest's home tenant is viral (unmanaged).
url: Properties of a B2B guest user - https://learn.microsoft.com/en-us/entra/external-id/user-properties
url: Reset redemption status for a guest user - https://learn.microsoft.com/en-us/entra/external-id/reset-redemption-status
#>
<#
.SYNOPSIS
    Exports a report of all guest accounts.
.DESCRIPTION
    Replaces create-GuestReport, create-GuestReportV2, create-GuestIsViralReport, create-GuestIsViralReportV2,
    get-GuestSponsors, get-MGEntraStaleGuest and Backup\export-Guests. Filter DaysSinceLastSignIn for stale guests.
    Guests in viral tenants can't be helped with a password reset; reset their redemption status and turn on email one-time passcode.
.PARAMETER CheckViral
    Look up each guest's home realm to see if it is a viral (unmanaged) tenant. Slower.
.EXAMPLE
    .\Get-GuestReport.ps1 -Environment Global -CheckViral
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$CheckViral,
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

function Test-ViralTenant {
    param([string]$Mail)
    if (-not $CheckViral -or -not $Mail) { return }
    $realm = Invoke-RestMethod -Uri "$loginEndpoint/common/userrealm/?user=$([uri]::EscapeDataString($Mail))&api-version=2.1" -ErrorAction SilentlyContinue
    [bool]($realm.IsViral -eq $true -or $realm.IsViral -eq "True")
}

function Get-LastDate {
    param($Guest)
    @($Guest.signInActivity.lastSignInDateTime, $Guest.signInActivity.lastNonInteractiveSignInDateTime, $Guest.signInActivity.lastSuccessfulSignInDateTime) |
        Where-Object { $_ } | ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1
}

function Format-Guest {
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $last = Get-LastDate -Guest $Guest
        $Guest | Select-Object id, displayName, userPrincipalName, mail, accountEnabled, externalUserState, externalUserStateChangeDateTime, createdDateTime, companyName, onPremisesSyncEnabled,
            @{ n = "Issuer"; e = { ($_.identities | Where-Object { $_.signInType -eq "federated" } | Select-Object -ExpandProperty issuer) -join ";" } },
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "LastSuccessfulSignInDateTime"; e = { $_.signInActivity.lastSuccessfulSignInDateTime } },
            @{ n = "DaysSinceLastSignIn"; e = { if ($last) { [int]((Get-Date) - $last).TotalDays } } },
            @{ n = "Sponsors"; e = { ($_.sponsors | ForEach-Object { if ($_.userPrincipalName) { $_.userPrincipalName } else { $_.displayName } }) -join ";" } },
            @{ n = "IsViral"; e = { Test-ViralTenant -Mail $_.mail } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "AuditLog.Read.All"
$loginEndpoint = (Get-MgEnvironment -Name $script:Environment).AzureADEndpoint

$file = Join-Path $Path "entra_guests.csv"
Write-Host "Getting guests"
"$script:Graph/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,mail,accountEnabled,externalUserState,externalUserStateChangeDateTime,createdDateTime,companyName,onPremisesSyncEnabled,identities,signInActivity&`$expand=sponsors(`$select=id,displayName,userPrincipalName)" |
    Get-GraphPage | Format-Guest | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
