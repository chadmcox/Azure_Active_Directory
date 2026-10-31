<#PSScriptInfo
.VERSION 2026.10
.GUID fa2d7e6c-82e8-4162-a28f-4ee0c9501219
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
Lists users who still have legacy per-user MFA turned on (enabled or enforced), which should be replaced with Conditional Access policies.
url: Enable per-user Microsoft Entra multifactor authentication - https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userstates
url: Get authentication requirements - https://learn.microsoft.com/en-us/graph/api/authentication-get?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports users whose per-user MFA state is enabled or enforced.
.DESCRIPTION
    Reads the per-user MFA state for each enabled member account, which takes a while in large tenants.
    Use -All to also list users where it is disabled.
.EXAMPLE
    .\Get-PerUserMfaState.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$All,
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

function Add-MfaState {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $state = try { (Invoke-MgGraphRequest -Uri "$script:Graph/users/$($User.id)/authentication/requirements" -OutputType PSObject -ErrorAction Stop).perUserMfaState } catch { "unknown" }
        $User | Select-Object id, userPrincipalName, onPremisesSyncEnabled, @{ n = "PerUserMfaState"; e = { $state } }
    }
}

Connect-Cloud -Scopes "User.Read.All", "Policy.Read.All", "UserAuthenticationMethod.Read.All"

$file = Join-Path $Path "entra_per_user_mfa.csv"
Write-Host "Reading per-user MFA state for every enabled member"
"$script:Graph/users?`$filter=userType eq 'Member' and accountEnabled eq true&`$select=id,userPrincipalName,onPremisesSyncEnabled,identityParentId&`$top=999" |
    Get-GraphPage | Where-Object { -not $_.identityParentId } | Add-MfaState |
    Where-Object { $All -or $_.PerUserMfaState -in "enabled", "enforced" } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
