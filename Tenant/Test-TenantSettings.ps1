<#PSScriptInfo
.VERSION 2026.10
.GUID 9ef32a78-a4dd-4811-906a-3cf88b7b119d
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
Checks tenant-wide settings against the Microsoft Entra operations reference guide (user and group settings, consent, guest access, password protection, password hash sync, notification contacts, emergency access accounts, named locations and legacy authentication blocking) and marks each one Pass or Review.
url: Microsoft Entra operations reference guide - https://learn.microsoft.com/en-us/entra/architecture/ops-guide-intro
#>
<#
.SYNOPSIS
    Checks tenant settings against the operations guide.
.DESCRIPTION
    Read only. Each row shows the current value, what the guide recommends and Pass or Review.
    "Review" means the setting differs from the guide; some organizations choose that on purpose.
.EXAMPLE
    .\Test-TenantSettings.ps1 -Environment Global
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

function Write-Check {
    param([string]$Area, [string]$Check, $Current, [string]$Recommended, [bool]$Pass, [string]$Link)
    $Check | Select-Object @{ n = "Area"; e = { $Area } }, @{ n = "Check"; e = { $_ } }, @{ n = "Current"; e = { "$Current" } },
        @{ n = "Recommended"; e = { $Recommended } }, @{ n = "Status"; e = { if ($Pass) { "Pass" } else { "Review" } } }, @{ n = "Guide"; e = { $Link } }
}

function Get-Setting {
    param([string]$Template, [string]$Name)
    ($groupSettings | Where-Object { $_.displayName -eq $Template }).values | Where-Object { $_.name -eq $Name } | Select-Object -ExpandProperty value -First 1
}

function Test-UserSettings {
    $auth = $authorization.defaultUserRolePermissions
    Write-Check "User settings" "Users can register apps" $auth.allowedToCreateApps "False" (-not $auth.allowedToCreateApps) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#user-settings"
    Write-Check "User settings" "Users can create security groups" $auth.allowedToCreateSecurityGroups "False" (-not $auth.allowedToCreateSecurityGroups) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#group-settings"
    $m365 = Get-Setting -Template "Group.Unified" -Name "EnableGroupCreation"
    Write-Check "User settings" "Users can create Microsoft 365 groups" $(if ($m365) { $m365 } else { "true (default)" }) "false, or limited to a group" ($m365 -eq "false") "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#group-settings"
    Write-Check "User settings" "Who can invite guests" $authorization.allowInvitesFrom "adminsAndGuestInviters or none" ($authorization.allowInvitesFrom -in "adminsAndGuestInviters", "none") "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#user-settings"
    # Well-known guest role IDs: restricted (most limited) and guest (limited, the default).
    $guestRole = switch ($authorization.guestUserRoleId) { "2af84b1e-32c8-42b7-82bc-daa82404023b" { "Restricted" } "10dae51f-b6af-4016-8d66-8c2a99b929b3" { "Limited" } default { "Same as members" } }
    Write-Check "User settings" "Guest user access" $guestRole "Restricted or Limited" ($guestRole -ne "Same as members") "https://learn.microsoft.com/en-us/entra/external-id/external-collaboration-settings-configure"
}

function Test-Consent {
    $userConsent = @($authorization.defaultUserRolePermissions.permissionGrantPoliciesAssigned | Where-Object { $_ -like "*permission-grant*" })
    Write-Check "Consent" "User consent to apps" $(if ($userConsent) { $userConsent -join ";" } else { "Off" }) "Off or low-risk (verified publishers) only" (-not $userConsent -or $userConsent -match "low") "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#consent-grants"
    $adminConsent = try { "$script:Graph/policies/adminConsentRequestPolicy" | Get-GraphPage | Select-Object -First 1 } catch { $null }
    Write-Check "Consent" "Admin consent request workflow" $adminConsent.isEnabled "True" ([bool]$adminConsent.isEnabled) "https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow"
}

function Test-Passwords {
    $banned = Get-Setting -Template "Password Rule Settings" -Name "EnableBannedPasswordCheck"
    $onPrem = Get-Setting -Template "Password Rule Settings" -Name "EnableBannedPasswordCheckOnPremises"
    $custom = Get-Setting -Template "Password Rule Settings" -Name "BannedPasswordList"
    Write-Check "Passwords" "Custom banned password list" $(if ($banned -eq "True") { "On ($(@($custom -split '\t' | Where-Object { $_ }).Count) words)" } else { "Off" }) "On" ($banned -eq "True") "https://learn.microsoft.com/en-us/entra/identity/authentication/concept-password-ban-bad"
    Write-Check "Passwords" "Password protection for on-premises AD" $(if ($onPrem) { $onPrem } else { "Not set" }) "True (enforced)" ($onPrem -eq "True") "https://learn.microsoft.com/en-us/entra/identity/authentication/howto-password-ban-bad-on-premises-deploy"
    if ($organization.onPremisesSyncEnabled) {
        Write-Check "Passwords" "Password hash sync" $sync.features.passwordSyncEnabled "True" ([bool]$sync.features.passwordSyncEnabled) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#on-premises-outage-authentication-resiliency"
    }
}

function Test-Notifications {
    $mails = @($organization.technicalNotificationMails | Where-Object { $_ })
    Write-Check "Notifications" "Technical notification contacts" $(if ($mails) { "$($mails.Count) address(es)" } else { "None" }) "A distribution list or shared mailbox" ($mails.Count -ge 1) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-ops#notifications"
}

function Test-EmergencyAccess {
    # Built-in template ID of the Global Administrator role.
    $ga = @("$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&`$expand=principal" | Get-GraphPage |
        Where-Object { $_.principal.'@odata.type' -eq "#microsoft.graph.user" })
    $users = @($ga | ForEach-Object { Invoke-MgGraphRequest -Uri "$script:Graph/users/$($_.principalId)?`$select=accountEnabled,onPremisesSyncEnabled,mail" -OutputType PSObject })
    $cloudOnly = @($users | Where-Object { $_.accountEnabled -and -not $_.onPremisesSyncEnabled })
    Write-Check "Privileged access" "Permanent Global Administrators" $ga.Count "Fewer than 5" ($ga.Count -lt 5) "https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices"
    Write-Check "Privileged access" "Cloud-only Global Administrators (emergency access)" $cloudOnly.Count "At least 2" ($cloudOnly.Count -ge 2) "https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access"
    Write-Check "Notifications" "Global Administrators with a mailbox" @($users | Where-Object { $_.mail }).Count "At least 2" (@($users | Where-Object { $_.mail }).Count -ge 2) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-ops#notifications"
}

function Test-AccessPolicies {
    $trusted = @($locations | Where-Object { $_.isTrusted })
    Write-Check "Access policies" "Trusted named locations" $trusted.Count "At least 1" ($trusted.Count -ge 1) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#named-locations"
    $legacy = @($policies | Where-Object { $_.state -eq "enabled" -and $_.grantControls.builtInControls -contains "block" -and
        ($_.conditions.clientAppTypes -contains "exchangeActiveSync" -or $_.conditions.clientAppTypes -contains "other") })
    Write-Check "Access policies" "Policy blocking legacy authentication" $(if ($legacy) { $legacy.displayName -join ";" } else { "None" }) "An enabled block policy" ([bool]$legacy) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#legacy-authentication"
    $risk = @($policies | Where-Object { $_.state -eq "enabled" -and ($_.conditions.userRiskLevels -or $_.conditions.signInRiskLevels) })
    Write-Check "Access policies" "Risk-based policies" $risk.Count "At least a user risk and a sign-in risk policy" ($risk.Count -ge 2) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#risk-based-access-policies"
    $allBlock = @($policies | Where-Object { $_.state -eq "enabled" -and $_.conditions.applications.includeApplications -contains "All" -and $_.grantControls.builtInControls -contains "block" -and
        $_.conditions.users.includeUsers -contains "All" -and -not $_.conditions.locations.includeLocations -and -not $_.conditions.platforms -and
        $_.conditions.clientAppTypes -contains "all" -and -not $_.conditions.userRiskLevels -and -not $_.conditions.signInRiskLevels })
    Write-Check "Access policies" "Block policies on All apps without conditions (lockout risk)" $allBlock.Count "0" ($allBlock.Count -eq 0) "https://learn.microsoft.com/en-us/entra/architecture/ops-guide-auth#conditional-access-implementation"
    $defaults = try { "$script:Graph/policies/identitySecurityDefaultsEnforcementPolicy" | Get-GraphPage | Select-Object -First 1 } catch { $null }
    Write-Check "Access policies" "Security defaults" $defaults.isEnabled "Off when Conditional Access is used" (-not ($defaults.isEnabled -and $policies)) "https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults"
}

Connect-Cloud -Scopes "Policy.Read.All", "Directory.Read.All", "Organization.Read.All", "RoleManagement.Read.Directory", "OnPremDirectorySynchronization.Read.All"

$authorization = "$script:Graph/policies/authorizationPolicy" | Get-GraphPage | Select-Object -First 1
$groupSettings = @("$script:Graph/groupSettings" | Get-GraphPage)
$organization = "$script:Graph/organization" | Get-GraphPage | Select-Object -First 1
$sync = try { "$script:Graph/directory/onPremisesSynchronization" | Get-GraphPage | Select-Object -First 1 } catch { $null }
$policies = @("$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage)
$locations = @("$script:Graph/identity/conditionalAccess/namedLocations" | Get-GraphPage)

$results = @(
    Test-UserSettings
    Test-Consent
    Test-Passwords
    Test-Notifications
    Test-EmergencyAccess
    Test-AccessPolicies
)
$results | Format-Table Area, Check, Current, Status -AutoSize | Out-Host
$file = Join-Path $Path "entra_tenant_settings_check.csv"
$results | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
