<#PSScriptInfo
.VERSION 2026.10
.GUID 5a6ba3cd-f825-42c0-8a18-eb420aa7977d
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
Shows which authentication methods are turned on in the Authentication methods policy, who each one targets, the migration state from the legacy MFA and SSPR policies, and the registration campaign settings.
url: Manage authentication methods for Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/authentication/concept-authentication-methods-manage
url: How to migrate MFA and SSPR policy settings to the Authentication methods policy - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-authentication-methods-manage
#>
<#
.SYNOPSIS
    Exports the Authentication methods policy as a readable table.
.DESCRIPTION
    One row per method with its state and included and excluded groups. Methods like SMS, voice and
    email OTP that are enabled for all users are worth reviewing against phishing-resistant options.
.EXAMPLE
    .\Get-AuthMethodsPolicy.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
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

function Resolve-Target {
    param([string]$Id)
    if ($Id -eq "all_users") { return "All users" }
    if (-not $names.ContainsKey($Id)) {
        $names[$Id] = try { (Invoke-MgGraphRequest -Uri "$script:Graph/groups/$($Id)?`$select=displayName" -OutputType PSObject -ErrorAction Stop).displayName } catch { $Id }
    }
    $names[$Id]
}

Connect-Cloud -Scopes "Policy.Read.All", "Group.Read.All"

$names = @{}
$policy = "$script:Graph/policies/authenticationMethodsPolicy" | Get-GraphPage | Select-Object -First 1
Write-Host "Migration state: $($policy.policyMigrationState)"
Write-Host "Registration campaign: $($policy.registrationEnforcement.authenticationMethodsRegistrationCampaign.state)"
Write-Host "System-preferred MFA: $($policy.systemCredentialPreferences.state)"
$file = Join-Path $Path "entra_authentication_methods_policy.csv"
$policy.authenticationMethodConfigurations | Select-Object @{ n = "Method"; e = { $_.id } }, state,
    @{ n = "IncludedTargets"; e = { ($_.includeTargets | ForEach-Object { Resolve-Target -Id $_.id }) -join ";" } },
    @{ n = "ExcludedTargets"; e = { ($_.excludeTargets | ForEach-Object { Resolve-Target -Id $_.id }) -join ";" } },
    @{ n = "MigrationState"; e = { $policy.policyMigrationState } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
