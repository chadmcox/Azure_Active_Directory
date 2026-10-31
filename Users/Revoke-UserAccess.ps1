<#PSScriptInfo
.VERSION 2026.10
.GUID 82094411-d53c-474f-a454-b7c292fb9d15
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
Cuts off a user in an emergency (for example a compromised account or an urgent termination): disables the account, revokes every refresh token and session, and disables the user's registered devices.
url: Revoke user access in an emergency in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access
#>
<#
.SYNOPSIS
    Disables a user, revokes their sessions and disables their devices.
.DESCRIPTION
    Access tokens already issued stay valid until they expire (usually about an hour) unless the app
    supports continuous access evaluation. For synced users, also disable the account in Active
    Directory, or sync will turn it back on. Reset the password and remove MFA methods separately if
    the account was compromised.
.PARAMETER KeepDevices
    Don't disable the user's registered devices.
.EXAMPLE
    .\Revoke-UserAccess.ps1 -Environment Global -UserPrincipalName "<person UPN>" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string[]]$UserPrincipalName,
    [switch]$KeepDevices
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

function Revoke-Access {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)][string]$Upn)
    process {
        $user = Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Upn)?`$select=id,userPrincipalName,accountEnabled,onPremisesSyncEnabled" -OutputType PSObject
        $disable = @{ accountEnabled = $false } | ConvertTo-Json
        if ($PSCmdlet.ShouldProcess($user.userPrincipalName, "Disable account")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($user.id)" -Method PATCH -Body $disable -ContentType "application/json"
            Write-Output "Disabled account $($user.userPrincipalName)"
        }
        if ($PSCmdlet.ShouldProcess($user.userPrincipalName, "Revoke all sessions and refresh tokens")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($user.id)/revokeSignInSessions" -Method POST | Out-Null
            Write-Output "Revoked sessions for $($user.userPrincipalName)"
        }
        if (-not $KeepDevices) {
            "$script:Graph/users/$($user.id)/registeredDevices?`$select=id,displayName,accountEnabled" | Get-GraphPage | Where-Object { $_.accountEnabled } | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.displayName, "Disable device")) {
                    Invoke-MgGraphRequest -Uri "$script:Graph/devices/$($_.id)" -Method PATCH -Body $disable -ContentType "application/json"
                    Write-Output "Disabled device $($_.displayName)"
                }
            }
        }
        if ($user.onPremisesSyncEnabled) { Write-Warning "$($user.userPrincipalName) is synced from Active Directory. Disable it there too." }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "User.RevokeSessions.All", "Device.ReadWrite.All"

$UserPrincipalName | Revoke-Access
