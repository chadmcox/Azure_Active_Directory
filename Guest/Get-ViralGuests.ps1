<#PSScriptInfo
.VERSION 2026.10
.GUID 5f8a1e82-22da-4f9f-a754-719158395a0a
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
Finds guests whose home tenant is a viral (unmanaged, self-service sign-up) Microsoft Entra tenant. Only the guest can reset their password there, so reset their redemption and turn on email one-time passcode.
url: Properties of a B2B guest user - https://learn.microsoft.com/en-us/entra/external-id/user-properties
url: Reset redemption status for a guest user - https://learn.microsoft.com/en-us/entra/external-id/reset-redemption-status
#>
<#
.SYNOPSIS
    Lists guests from viral (unmanaged) tenants.
.DESCRIPTION
    Replaces create-GuestIsViralReport and create-GuestIsViralReportV2. Each email domain is looked up
    once. Pass the CSV to Reset-GuestRedemption.ps1 -CsvPath to move these guests to email one-time
    passcode.
.EXAMPLE
    .\Get-ViralGuests.ps1 -Environment Global
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

function Test-ViralTenant {
    param([string]$Mail)
    $domain = ($Mail -split "@")[-1]
    if (-not $realmCache.ContainsKey($domain)) {
        $realm = Invoke-RestMethod -Uri "$loginEndpoint/common/userrealm/?user=$([uri]::EscapeDataString($Mail))&api-version=2.1" -ErrorAction SilentlyContinue
        $realmCache[$domain] = [bool]($realm.IsViral -eq $true -or $realm.IsViral -eq "True")
    }
    $realmCache[$domain]
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
$realmCache = @{}
$loginEndpoint = (Get-MgEnvironment -Name $script:Environment).AzureADEndpoint

$file = Join-Path $Path "entra_viral_guests.csv"
Write-Host "Getting guests"
"$script:Graph/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,mail,accountEnabled,externalUserState,externalUserStateChangeDateTime,createdDateTime,companyName,onPremisesSyncEnabled,identities,signInActivity&`$expand=sponsors(`$select=id,displayName,userPrincipalName)" |
    Get-GraphPage | Where-Object { $_.mail } | Format-Guest | Where-Object { $_.IsViral } | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
