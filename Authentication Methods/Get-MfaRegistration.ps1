<#PSScriptInfo
.VERSION 2026.10
.GUID 4c227310-8f67-4340-bf48-2b0dcb0c3b6e
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
Reports MFA, SSPR and passwordless registration for members or guests, and flags users who have phone numbers or alternate emails on their account but no registered methods (prepopulated).
url: List userRegistrationDetails - https://learn.microsoft.com/en-us/graph/api/authenticationmethodsroot-list-userregistrationdetails?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports authentication method registration details.
.DESCRIPTION
    Replaces create-AADUserMFAReport, create-AADGuestMFAReport, create-AADWH4BRegisteredUsers,
    get-HybridUserMFAandSSPRState and get-UserSMSPrepopulated.
.PARAMETER UserType
    Member, Guest or All.
.PARAMETER Method
    Only users with this method registered, for example windowsHelloForBusiness, fido2, microsoftAuthenticatorPush, mobilePhone.
.PARAMETER SyncedOnly
    Only users synced from on-premises Active Directory.
.EXAMPLE
    .\Get-MfaRegistration.ps1 -Environment Global -UserType Member -SyncedOnly
.EXAMPLE
    .\Get-MfaRegistration.ps1 -Environment Global -Method windowsHelloForBusiness
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [ValidateSet("Member", "Guest", "All")][string]$UserType = "Member",
    [string]$Method,
    [switch]$SyncedOnly,
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

function Format-Registration {
    param([Parameter(ValueFromPipeline)]$Registration)
    process {
        $user = $users[$Registration.id]
        if ($SyncedOnly -and -not $user.onPremisesSyncEnabled) { return }
        $Registration | Select-Object id, userPrincipalName, userDisplayName, userType,
            @{ n = "AccountEnabled"; e = { $user.accountEnabled } },
            @{ n = "OnPremisesSyncEnabled"; e = { [bool]$user.onPremisesSyncEnabled } },
            isAdmin, isMfaCapable, isMfaRegistered, isPasswordlessCapable, isSsprCapable, isSsprEnabled, isSsprRegistered,
            isSystemPreferredAuthenticationMethodEnabled, defaultMfaMethod,
            @{ n = "MethodsRegistered"; e = { $_.methodsRegistered -join ";" } },
            @{ n = "Prepopulated"; e = { @($_.methodsRegistered).Count -eq 0 -and ($user.mobilePhone -or $user.businessPhones -or $user.otherMails) } },
            lastUpdatedDateTime
    }
}

Connect-Cloud -Scopes "AuditLog.Read.All", "UserAuthenticationMethod.Read.All", "User.Read.All"

$filters = @(
    if ($UserType -ne "All") { "userType eq '$($UserType.ToLower())'" }
    if ($Method) { "methodsRegistered/any(m:m eq '$Method')" }
)
$query = if ($filters) { "?`$filter=$($filters -join ' and ')" } else { "" }

Write-Host "Getting users"
$users = "$script:Graph/users?`$select=id,accountEnabled,onPremisesSyncEnabled,mobilePhone,businessPhones,otherMails&`$top=999" | Get-GraphPage | Group-Object id -AsHashTable -AsString
$file = Join-Path $Path "entra_mfa_registration_$UserType.csv"
Write-Host "Getting registration details"
"$script:Graph/reports/authenticationMethods/userRegistrationDetails$query" | Get-GraphPage |
    Format-Registration | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
