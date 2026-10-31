<#PSScriptInfo
.VERSION 2026.10
.GUID 0eb18604-bd1e-4052-a995-8045ef9468fd
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
Removes directly assigned licenses from disabled accounts and accounts that have not signed in for a set number of days, from a reviewed Get-StaleLicenses.ps1 report or found live. Licenses that come from a group are left alone. Runs interactively or as an Azure Automation runbook with a managed identity.
url: user: assignLicense - https://learn.microsoft.com/en-us/graph/api/user-assignlicense?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes direct license assignments from stale accounts.
.DESCRIPTION
    Every account is checked again before a license is removed, so an account that was enabled or signed
    in after the report was made is skipped. Removing a license starts the service's data retention
    period (for example 30 days for an Exchange mailbox), so review the report first.
.PARAMETER CsvPath
    A reviewed Get-StaleLicenses.ps1 report. Without it, stale licenses are found live.
.PARAMETER Days
    Days without a sign-in. Default 90.
.PARAMETER DisabledOnly
    Only remove licenses from disabled accounts.
.PARAMETER MaxRemovals
    Stop after this many users, as a safety limit. Default 25.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-StaleLicenses.ps1 -Environment Global -CsvPath .\entra_stale_licenses.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath,
    [int]$Days = 90,
    [switch]$DisabledOnly,
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
    $select = "id,userPrincipalName,accountEnabled,createdDateTime,licenseAssignmentStates,signInActivity"
    if ($CsvPath) {
        Import-Csv $CsvPath | Select-Object -ExpandProperty UserId -Unique |
            ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_)?`$select=$select" -OutputType PSObject }
    } else {
        "$script:Graph/users?`$filter=assignedLicenses/`$count ne 0&`$count=true&`$select=$select&`$top=999" | Get-GraphPage -Eventual
    }
}

function Select-Stale {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $last = @($User.signInActivity.lastSignInDateTime, $User.signInActivity.lastNonInteractiveSignInDateTime) | Where-Object { $_ } |
            ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1
        $stale = (-not $User.accountEnabled) -or (-not $DisabledOnly -and (-not $User.createdDateTime -or [datetime]$User.createdDateTime -lt $cutoff) -and (-not $last -or $last -lt $cutoff))
        $direct = @($User.licenseAssignmentStates | Where-Object { $_ -and -not $_.assignedByGroup } | Select-Object -ExpandProperty skuId -Unique)
        if ($wanted) { $direct = @($direct | Where-Object { $wanted.ContainsKey("$($User.id)|$_") }) }
        if ($stale -and $direct) { $User | Select-Object id, userPrincipalName, accountEnabled, @{ n = "SkuIds"; e = { $direct } } }
    }
}

function Remove-License {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $names = ($User.SkuIds | ForEach-Object { $skuNames[[string]$_] }) -join ";"
        $action = if ($PSCmdlet.ShouldProcess($User.userPrincipalName, "Remove licenses $names")) {
            $body = @{ addLicenses = @(); removeLicenses = @($User.SkuIds) } | ConvertTo-Json
            Invoke-MgGraphRequest -Uri "$script:Graph/users/$($User.id)/assignLicense" -Method POST -Body $body -ContentType "application/json" | Out-Null
            "Removed"
        } else { "WhatIf" }
        $User | Select-Object id, userPrincipalName, accountEnabled, @{ n = "Licenses"; e = { $names } }, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "User.ReadWrite.All", "Organization.Read.All", "AuditLog.Read.All" -Identity:$Identity

$cutoff = (Get-Date).AddDays(-$Days)
$skuNames = @{}
"$script:Graph/subscribedSkus" | Get-GraphPage | ForEach-Object { $skuNames[[string]$_.skuId] = $_.skuPartNumber }
$wanted = if ($CsvPath) { Import-Csv $CsvPath | Group-Object { "$($_.UserId)|$($_.skuId)" } -AsHashTable -AsString } else { $null }

$results = Get-Candidates | Select-Stale | Select-Object -First $MaxRemovals | Remove-License
$results | Format-Table userPrincipalName, Licenses, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_stale_licenses_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
