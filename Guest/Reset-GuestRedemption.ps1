<#PSScriptInfo
.VERSION 2026.10
.GUID 84a3069c-58ca-4498-8624-3358e6a8cbed
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
Resets the redemption status of guests so they can sign in again with a different account or method (for example after leaving their home company or when their home tenant is a viral tenant) without losing their group memberships and app access.
url: Reset redemption status for a guest user - https://learn.microsoft.com/en-us/entra/external-id/reset-redemption-status
#>
<#
.SYNOPSIS
    Resets guest redemption and sends a new invitation.
.DESCRIPTION
    Takes guest UPNs, or a CSV with an id column (for example the viral guests from
    Get-GuestReport.ps1 -CheckViral). Use -NoEmail to reset without sending the invitation email.
.EXAMPLE
    .\Reset-GuestRedemption.ps1 -Environment Global -UserPrincipalName "<guest UPN>" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string[]]$UserPrincipalName,
    [string]$CsvPath,
    [string]$RedirectUrl = "https://myapps.microsoft.com",
    [switch]$NoEmail
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

function Reset-Guest {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)][string]$Id)
    process {
        $guest = Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Id)?`$select=id,userPrincipalName,mail,userType" -OutputType PSObject
        if ($guest.userType -ne "Guest" -or -not $guest.mail) { Write-Warning "$Id is not a guest with a mail address"; return }
        if (-not $PSCmdlet.ShouldProcess($guest.mail, "Reset redemption")) { return }
        $body = @{
            invitedUserEmailAddress = $guest.mail
            inviteRedirectUrl       = $RedirectUrl
            sendInvitationMessage   = -not $NoEmail
            invitedUser             = @{ id = $guest.id }
            resetRedemption         = $true
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Uri "$script:Graph/invitations" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject |
            Select-Object @{ n = "Guest"; e = { $guest.mail } }, status, inviteRedeemUrl
    }
}

Connect-Cloud -Scopes "User.Invite.All", "User.ReadWrite.All"

@(
    $UserPrincipalName
    if ($CsvPath) { Import-Csv $CsvPath | Select-Object -ExpandProperty id }
) | Where-Object { $_ } | Reset-Guest | Format-Table -AutoSize
