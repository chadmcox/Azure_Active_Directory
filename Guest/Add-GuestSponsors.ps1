<#PSScriptInfo
.VERSION 2026.10
.GUID 2f90838a-278d-4dc3-baee-1fb554de9260
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
Sets the person who invited each guest as the guest's sponsor, using the "Invite external user" audit events. Runs interactively or as a daily Azure Automation runbook with a managed identity.
url: Add sponsors - https://learn.microsoft.com/en-us/graph/api/user-post-sponsors?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Adds the inviting user as sponsor on guests that have none.
.DESCRIPTION
    Replaces add-AADSponsoronGuest. The no-module runbook version is Maintenance Task\runbook-AADAddSponsortoGuest. Audit logs only go
    back 30 days, so run it on a schedule.
.PARAMETER Days
    How many days of invite events to read. Default 30.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Add-GuestSponsors.ps1 -Environment Global -Days 7 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 30,
    [switch]$Identity
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

function Add-Sponsor {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Invite)
    process {
        $guestId = ($Invite.targetResources | Select-Object -First 1).id
        $sponsorId = $Invite.initiatedBy.user.id
        if (-not $guestId -or -not $sponsorId) { return }
        $existing = try { "$script:Graph/users/$guestId/sponsors?`$select=id" | Get-GraphPage } catch { Write-Warning "Guest $guestId not found"; return }
        if ($existing) { return }
        if ($PSCmdlet.ShouldProcess($guestId, "Add sponsor $($Invite.initiatedBy.user.userPrincipalName)")) {
            $body = @{ "@odata.id" = "$script:Graph/users/$sponsorId" } | ConvertTo-Json
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$guestId/sponsors/`$ref" -Method POST -Body $body -ContentType "application/json"
            Write-Output "Added $($Invite.initiatedBy.user.userPrincipalName) as sponsor of $guestId"
        }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
"$script:Graph/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Invite external user' and result eq 'success' and activityDateTime ge $since" |
    Get-GraphPage | Add-Sponsor
