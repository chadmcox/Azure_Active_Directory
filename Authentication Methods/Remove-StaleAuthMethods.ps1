<#PSScriptInfo
.VERSION 2026.10
.GUID f407fdbe-8963-4827-943b-a697faa4e2f9
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
Removes stale authentication methods (not used for a set number of days) from users, never removing a user's last MFA method. Unassigned hardware OATH tokens are removed by Remove-UnassignedHardwareTokens.ps1. Works from a reviewed Get-StaleAuthMethods.ps1 report or finds them live. Runs interactively or as an Azure Automation runbook with a managed identity.
url: Manage user authentication methods - https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userdevicesettings
#>
<#
.SYNOPSIS
    Removes stale authentication methods.
.DESCRIPTION
    Every method is checked again before it is removed. Passwords and Temporary Access Passes are never
    touched. A method is skipped if it is the user's only remaining MFA method.
.PARAMETER CsvPath
    A reviewed Get-StaleAuthMethods.ps1 report. Without it, stale methods are found live.
.PARAMETER Days
    Days without use. Default 180.
.PARAMETER MaxRemovals
    Stop after this many methods, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleAuthMethods.ps1 -Environment Global -CsvPath .\entra_stale_auth_methods.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$Days = 180,
    [int]$MaxRemovals = 25,
    [switch]$Identity,
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

$collections = @{
    microsoftAuthenticatorAuthenticationMethod = "microsoftAuthenticatorMethods"
    phoneAuthenticationMethod                  = "phoneMethods"
    fido2AuthenticationMethod                  = "fido2Methods"
    windowsHelloForBusinessAuthenticationMethod = "windowsHelloForBusinessMethods"
    softwareOathAuthenticationMethod           = "softwareOathMethods"
    hardwareOathAuthenticationMethod           = "hardwareOathMethods"
    emailAuthenticationMethod                  = "emailMethods"
    platformCredentialAuthenticationMethod     = "platformCredentialMethods"
}

function Get-Users {
    if ($CsvPath) {
        Import-Csv $CsvPath | Where-Object { $_.UserId } | Select-Object @{ n = "id"; e = { $_.UserId } }, @{ n = "userPrincipalName"; e = { $_.UserPrincipalName } } -Unique
    } else {
        "$script:Graph/reports/authenticationMethods/userRegistrationDetails" | Get-GraphPage | Where-Object { $_.methodsRegistered } | Select-Object id, userPrincipalName
    }
}

function Get-StaleMethods {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $u = $User
        $methods = @("$script:Graph/users/$($u.id)/authentication/methods" | Get-GraphPage | Where-Object { $_.'@odata.type' -notmatch "password|temporaryAccessPass" })
        $stale = @($methods | Where-Object {
            $when = if ($_.lastUsedDateTime) { $_.lastUsedDateTime } else { $_.createdDateTime }
            $when -and [datetime]$when -lt $cutoff -and (-not $wanted -or $wanted.ContainsKey($_.id))
        })
        # Never remove every method a user has.
        $keep = if ($stale.Count -ge $methods.Count) { 1 } else { 0 }
        $stale | Select-Object -Skip $keep | Select-Object @{ n = "UserId"; e = { $u.id } }, @{ n = "UserPrincipalName"; e = { $u.userPrincipalName } },
            @{ n = "MethodType"; e = { ($_.'@odata.type' -split "\.")[-1] } }, @{ n = "MethodId"; e = { $_.id } }, displayName, lastUsedDateTime
    }
}

function Remove-Method {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Method)
    process {
        $uri = if ($collections.ContainsKey($Method.MethodType)) { "$script:Graph/users/$($Method.UserId)/authentication/$($collections[$Method.MethodType])/$($Method.MethodId)" }
        $action = if (-not $uri) { "Skipped - unsupported type" }
            elseif ($PSCmdlet.ShouldProcess("$($Method.UserPrincipalName) $($Method.MethodType) $($Method.displayName)", "Remove")) {
                Invoke-MgGraphRequest -Uri $uri -Method DELETE
                "Removed"
            } else { "WhatIf" }
        $Method | Select-Object UserPrincipalName, MethodType, MethodId, displayName, lastUsedDateTime, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "UserAuthenticationMethod.ReadWrite.All", "AuditLog.Read.All", "Policy.ReadWrite.AuthenticationMethod" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$wanted = if ($CsvPath) { Import-Csv $CsvPath | Group-Object MethodId -AsHashTable -AsString } else { $null }
$results = @(
    Get-Users | Get-StaleMethods
) | Select-Object -First $MaxRemovals | Remove-Method
$results | Format-Table UserPrincipalName, MethodType, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_auth_methods_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
