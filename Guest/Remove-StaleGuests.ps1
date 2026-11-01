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
Deletes guests that accepted their invitation but have not signed in for a set number of days, either from a reviewed Get-StaleGuests.ps1 report or by finding them live. Runs interactively or as an Azure Automation runbook with a managed identity. Deleted guests stay in the recycle bin for 30 days.
url: How to manage inactive user accounts - https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-manage-inactive-user-accounts
url: Delete a user - https://learn.microsoft.com/en-us/graph/api/user-delete?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes guests that have not signed in for a set number of days.
.DESCRIPTION
    Replaces remove-StaleGuest and Maintenance Task\runbook-removeAADStaleGuest (still kept as a
    no-module runbook). Every guest is checked again before deletion, so a guest who signed in after the
    report was made is skipped. Guests with pending invitations are handled by Remove-PendingGuests.ps1.
.PARAMETER CsvPath
    A reviewed Get-StaleGuests.ps1 report. Without it, stale guests are found live.
.PARAMETER Days
    Days without a sign-in. Default 90.
.PARAMETER MaxRemovals
    Stop after this many deletions, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleGuests.ps1 -Environment Global -CsvPath .\entra_stale_guests.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$Days = 90,
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

function Get-Candidates {
    $select = "id,userPrincipalName,mail,userType,createdDateTime,externalUserState,externalUserStateChangeDateTime,signInActivity"
    if ($CsvPath) {
        Import-Csv $CsvPath | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_.id)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/users?`$filter=userType eq 'Guest'&`$select=$select" | Get-GraphPage
    }
}

function Get-StaleReason {
    param($Guest)
    if ($Guest.userType -ne "Guest" -or $Guest.externalUserState -eq "PendingAcceptance") { return }
    $cutoff = (Get-Date).AddDays(-$Days)
    $recent = @($Guest.signInActivity.lastSignInDateTime, $Guest.signInActivity.lastNonInteractiveSignInDateTime, $Guest.signInActivity.lastSuccessfulSignInDateTime, $Guest.createdDateTime) |
        Where-Object { $_ -and [datetime]$_ -ge $cutoff }
    if (-not $recent) { "Inactive" }
}

function Remove-Guest {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Guest)
    process {
        $reason = Get-StaleReason -Guest $Guest
        $action = if ($PSCmdlet.ShouldProcess($Guest.userPrincipalName, "Delete $reason guest")) {
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Guest.id)" -Method DELETE
            "Deleted"
        } else { "WhatIf" }
        $Guest | Select-Object id, userPrincipalName, mail, externalUserState, externalUserStateChangeDateTime, createdDateTime,
            @{ n = "StaleReason"; e = { $reason } },
            @{ n = "LastSignInDateTime"; e = { $_.signInActivity.lastSignInDateTime } },
            @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "AuditLog.Read.All" -Identity:$Identity

$results = Get-Candidates | Where-Object { Get-StaleReason -Guest $_ } | Select-Object -First $MaxRemovals | Remove-Guest
$results | Format-Table userPrincipalName, StaleReason, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_guests_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
