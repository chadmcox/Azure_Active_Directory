<#PSScriptInfo
.VERSION 2026.10
.GUID f1cb4f3f-903d-4712-922a-a995595ea96a
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
Finds stale authentication methods: registered methods (Authenticator, phone, FIDO2, Windows Hello, software and hardware OATH, email) not used for a set number of days. Unassigned hardware OATH tokens are in Get-UnassignedHardwareTokens.ps1.
url: Manage user authentication methods - https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userdevicesettings
url: List authentication methods - https://learn.microsoft.com/en-us/graph/api/authentication-list-methods?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Creates a stale authentication method report.
.DESCRIPTION
    A method is stale when its last use (or, if never used, its registration) is older than the window.
    Passwords and Temporary Access Passes are left out. OnlyMethod shows when removing it would leave
    the user with no MFA method, so it won't be removed.
    Review the CSV, remove rows to keep, then pass it to Remove-StaleAuthMethods.ps1 -CsvPath.
.PARAMETER Days
    Days without use. Default 180.
.EXAMPLE
    .\Get-StaleAuthMethods.ps1 -Environment Global -Days 180
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 180,
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

function Get-StaleMethods {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $u = $User
        $methods = @("$script:Graph/users/$($u.id)/authentication/methods" | Get-GraphPage |
            Where-Object { $_.'@odata.type' -notmatch "password|temporaryAccessPass" })
        $methods | Where-Object {
            $when = if ($_.lastUsedDateTime) { $_.lastUsedDateTime } else { $_.createdDateTime }
            $when -and [datetime]$when -lt $cutoff
        } | Select-Object @{ n = "UserPrincipalName"; e = { $u.userPrincipalName } }, @{ n = "UserId"; e = { $u.id } },
            @{ n = "MethodType"; e = { ($_.'@odata.type' -split "\.")[-1] } }, @{ n = "MethodId"; e = { $_.id } },
            displayName, phoneNumber, createdDateTime, lastUsedDateTime,
            @{ n = "OnlyMethod"; e = { $methods.Count -eq 1 } },
            @{ n = "Remediation"; e = { if ($methods.Count -eq 1) { "Keep - only method" } else { "Remove-StaleAuthMethods.ps1" } } }
    }
}

Connect-Cloud -Scopes "UserAuthenticationMethod.Read.All", "AuditLog.Read.All", "Policy.Read.AuthenticationMethod"

$cutoff = (Get-Date).AddDays(-$Days)
$file = Join-Path $Path "entra_stale_auth_methods.csv"
Write-Host "Reading methods for users with registered methods (this can take a while)"
@(
    "$script:Graph/reports/authenticationMethods/userRegistrationDetails" | Get-GraphPage |
        Where-Object { $_.methodsRegistered } | Select-Object id, userPrincipalName | Get-StaleMethods
) | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
