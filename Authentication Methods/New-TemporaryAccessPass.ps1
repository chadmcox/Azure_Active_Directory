<#PSScriptInfo
.VERSION 2026.10
.GUID f4c1ed84-1273-4435-9dc2-686b9a88d1e7
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
Creates a Temporary Access Pass for one or more users so they can sign in and register passwordless or MFA methods (new hires, lost phones, account recovery). The pass is shown on screen once and never written to disk.
url: Configure a Temporary Access Pass - https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass
#>
<#
.SYNOPSIS
    Creates Temporary Access Passes.
.DESCRIPTION
    The Temporary Access Pass method must be enabled in the Authentication methods policy, and the
    lifetime must fit inside the policy's minimum and maximum. Give the pass to the user through a
    trusted channel.
.PARAMETER LifetimeInMinutes
    How long the pass works. Default 60.
.PARAMETER MultipleUse
    Let the pass be used more than once during its lifetime. One-time use is the default.
.EXAMPLE
    .\New-TemporaryAccessPass.ps1 -Environment Global -UserPrincipalName "<person UPN>" -LifetimeInMinutes 480
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string[]]$UserPrincipalName,
    [int]$LifetimeInMinutes = 60,
    [switch]$MultipleUse
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

function New-Pass {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)][string]$Upn)
    process {
        if (-not $PSCmdlet.ShouldProcess($Upn, "Create Temporary Access Pass for $LifetimeInMinutes minutes")) { return }
        $body = @{ lifetimeInMinutes = $LifetimeInMinutes; isUsableOnce = -not $MultipleUse } | ConvertTo-Json
        Invoke-MgGraphRequest -Uri "$script:Graph/users/$Upn/authentication/temporaryAccessPassMethods" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject |
            Select-Object @{ n = "User"; e = { $Upn } }, temporaryAccessPass, startDateTime, lifetimeInMinutes, isUsableOnce
    }
}

Connect-Cloud -Scopes "UserAuthenticationMethod.ReadWrite.All"

$UserPrincipalName | New-Pass | Format-Table -AutoSize
