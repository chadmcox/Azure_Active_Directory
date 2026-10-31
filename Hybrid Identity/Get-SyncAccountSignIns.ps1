<#PSScriptInfo
.VERSION 2026.10
.GUID dc62b9ce-b437-45f3-b628-f2f546722229
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
Lists the IP addresses and apps used by Directory Synchronization Accounts (Entra Connect sync accounts), to confirm they only sign in from the sync servers.
url: Directory Synchronization Accounts role - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#directory-synchronization-accounts
#>
<#
.SYNOPSIS
    Summarizes sign-ins by Entra Connect sync accounts.
.DESCRIPTION
    Replaces Azure AD Connect\GetSyncAccountIPs and getSyncAccountSigninApps.
.PARAMETER Days
    Days of sign-ins to read. Default 7.
.EXAMPLE
    .\Get-SyncAccountSignIns.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$Days = 7,
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

function Get-SignIns {
    param([Parameter(ValueFromPipeline)]$Account)
    process {
        "$script:Graph/auditLogs/signIns?`$filter=userId eq '$($Account.id)' and createdDateTime ge $since" | Get-GraphPage
        "$script:Graph/auditLogs/signIns?`$filter=userId eq '$($Account.id)' and createdDateTime ge $since and signInEventTypes/any(t: t eq 'nonInteractiveUser')" | Get-GraphPage
    }
}

Connect-Cloud -Scopes "AuditLog.Read.All", "RoleManagement.Read.Directory"

# Built-in template ID of the Directory Synchronization Accounts role.
$syncRoleId = "d29b2b05-8046-44ba-8758-1e26182fcf32"
$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_sync_account_signins.csv"
"$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$syncRoleId'&`$expand=principal" | Get-GraphPage |
    Where-Object { $_.principal.'@odata.type' -eq "#microsoft.graph.user" } |
    Select-Object @{ n = "id"; e = { $_.principal.id } } |
    Get-SignIns |
    Group-Object userPrincipalName, ipAddress, appDisplayName, { $_.status.errorCode -eq 0 } |
    Select-Object @{ n = "UserPrincipalName"; e = { $_.Group[0].userPrincipalName } },
        @{ n = "IpAddress"; e = { $_.Group[0].ipAddress } },
        @{ n = "App"; e = { $_.Group[0].appDisplayName } },
        @{ n = "Success"; e = { $_.Group[0].status.errorCode -eq 0 } },
        @{ n = "SignIns"; e = { $_.Count } },
        @{ n = "LastSeen"; e = { ($_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1) } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
