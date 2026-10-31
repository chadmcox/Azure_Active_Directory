<#PSScriptInfo
.VERSION 2026.10
.GUID 0b8726bd-ad68-4337-b4eb-b7c38c9e178e
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
Deletes guests that have not signed in for a set number of days, or that never accepted their invitation. Runs interactively or as an Azure Automation runbook with a managed identity. Deleted guests stay in the recycle bin for 30 days.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
url: Delete a user - https://learn.microsoft.com/en-us/graph/api/user-delete?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes inactive guests or guests with pending invitations.
.DESCRIPTION
    Replaces remove-StaleGuest, remove-StalePendingGuest, and Maintenance Task\runbook-removeAADStaleGuest
    and runbook-removeAADUnacceptedGuest.
.PARAMETER Mode
    Inactive - guests with no sign-in (interactive or not) in -Days days.
    PendingAcceptance - guests who have not accepted an invite sent more than -Days days ago.
.PARAMETER MaxRemovals
    Stop after this many deletions, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleGuests.ps1 -Environment Global -Mode Inactive -Days 180 -WhatIf
.EXAMPLE
    .\Remove-StaleGuests.ps1 -Environment Global -Mode PendingAcceptance -Days 15 -Identity
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("Inactive", "PendingAcceptance")][string]$Mode = "Inactive",
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

function Test-Stale {
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $cutoff = (Get-Date).AddDays(-$Days)
        $stale = if ($Mode -eq "PendingAcceptance") {
            $Guest.externalUserState -eq "PendingAcceptance" -and [datetime]$Guest.externalUserStateChangeDateTime -lt $cutoff
        } else {
            $dates = @($Guest.signInActivity.lastSignInDateTime, $Guest.signInActivity.lastNonInteractiveSignInDateTime) | Where-Object { $_ }
            [datetime]$Guest.createdDateTime -lt $cutoff -and -not ($dates | Where-Object { [datetime]$_ -ge $cutoff })
        }
        if ($stale) { $Guest }
    }
}

function Remove-Guest {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $action = if ($PSCmdlet.ShouldProcess($Guest.userPrincipalName, "Delete guest")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Guest.id)" -Method DELETE
            "Deleted"
        } else { "WhatIf" }
        $Guest | Select-Object id, userPrincipalName, mail, externalUserState, externalUserStateChangeDateTime, createdDateTime,
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "LastNonInteractiveSignInDateTime"; e = { $_.signInActivity.lastNonInteractiveSignInDateTime } },
            @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

$results = "$script:Graph/users?`$filter=userType eq 'Guest'&`$select=id,userPrincipalName,mail,externalUserState,externalUserStateChangeDateTime,createdDateTime,signInActivity" |
    Get-GraphPage | Test-Stale | Select-Object -First $MaxRemovals | Remove-Guest
$results | Format-Table userPrincipalName, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_guests_removed_$Mode.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
