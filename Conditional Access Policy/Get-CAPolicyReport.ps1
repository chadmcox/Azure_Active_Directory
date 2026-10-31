<#PSScriptInfo
.VERSION 2026.10
.GUID 72b294d4-4148-4efb-bfb5-ea177e576762
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
Reports each Conditional Access policy with how many users it targets and excludes (through users, groups, roles and guests), its apps, conditions, grant and session controls.
url: Building a Conditional Access policy - https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policies
#>
<#
.SYNOPSIS
    Exports Conditional Access policies with targeted and excluded user counts.
.DESCRIPTION
    Replaces count-usersperconditionalaccesspolicy and Backup\export-ConditionalAccessPolicy.
.PARAMETER BackupJson
    Also save each policy as a JSON file.
.EXAMPLE
    .\Get-CAPolicyReport.ps1 -Environment Global -BackupJson
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [switch]$BackupJson,
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

function Get-Count {
    param([string]$Uri)
    [int](Invoke-MgGraphRequest -Uri $Uri -Headers @{ ConsistencyLevel = "eventual" })
}

function Get-TargetCount {
    param($Users, [string]$Side)
    $userList = $Users."$($Side)Users"
    if ($userList -contains "All") { return "All ($($totalUsers + $totalGuests))" }
    $counts = @(
        @($userList | Where-Object { $_ -notin "GuestsOrExternalUsers", "None" }).Count
        $Users."$($Side)Groups" | ForEach-Object {
            if (-not $groupCounts.ContainsKey($_)) { $groupCounts[$_] = Get-Count -Uri "$script:Graph/groups/$_/transitiveMembers/`$count" }
            $groupCounts[$_]
        }
        $Users."$($Side)Roles" | ForEach-Object {
            if (-not $roleCounts.ContainsKey($_)) { $roleCounts[$_] = @("$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$_'" | Get-GraphPage | Select-Object principalId -Unique).Count }
            $roleCounts[$_]
        }
        if ($Users."$($Side)GuestsOrExternalUsers" -or $userList -contains "GuestsOrExternalUsers") { $totalGuests }
    )
    ($counts | Measure-Object -Sum).Sum
}

function Resolve-App {
    param([string]$AppId)
    if ($AppId -notmatch "^[0-9a-fA-F-]{36}$") { return $AppId }
    if (-not $appNames.ContainsKey($AppId)) {
        $appNames[$AppId] = ("$script:Graph/servicePrincipals?`$filter=appId eq '$AppId'&`$select=displayName" | Get-GraphPage | Select-Object -First 1).displayName
    }
    $appNames[$AppId]
}

function Resolve-Object {
    param([string]$Id, [switch]$Role)
    if ($Id -notmatch "^[0-9a-fA-F-]{36}$") { return $Id }
    if (-not $objectNames.ContainsKey($Id)) {
        $uri = if ($Role) { "$script:Graph/roleManagement/directory/roleDefinitions/$Id" } else { "$script:Graph/directoryObjects/$Id" }
        $found = try { Invoke-MgGraphRequest -Uri $uri -OutputType PSObject -ErrorAction Stop } catch { $null }
        $objectNames[$Id] = if ($found.userPrincipalName) { $found.userPrincipalName } elseif ($found.displayName) { $found.displayName } else { "$Id (not found)" }
    }
    $objectNames[$Id]
}

function Get-TargetNames {
    param($Users, [string]$Side)
    @(
        $Users."$($Side)Users" | ForEach-Object { Resolve-Object -Id $_ }
        $Users."$($Side)Groups" | ForEach-Object { "group:" + (Resolve-Object -Id $_) }
        $Users."$($Side)Roles" | ForEach-Object { "role:" + (Resolve-Object -Id $_ -Role) }
        if ($Users."$($Side)GuestsOrExternalUsers") { "guests:" + $Users."$($Side)GuestsOrExternalUsers".guestOrExternalUserTypes }
    ) -join ";"
}

function Format-Policy {
    param([Parameter(ValueFromPipeline)]$Policy)
    process {
        Write-Host "  $($Policy.displayName)"
        $Policy | Select-Object @{ n = "Policy"; e = { $_.displayName } }, state,
            @{ n = "TargetedUserCount"; e = { Get-TargetCount -Users $_.conditions.users -Side include } },
            @{ n = "ExcludedUserCount"; e = { Get-TargetCount -Users $_.conditions.users -Side exclude } },
            @{ n = "Included"; e = { Get-TargetNames -Users $_.conditions.users -Side include } },
            @{ n = "Excluded"; e = { Get-TargetNames -Users $_.conditions.users -Side exclude } },
            @{ n = "GrantControls"; e = { $_.grantControls.builtInControls -join " $($_.grantControls.operator) " } },
            @{ n = "AuthenticationStrength"; e = { $_.grantControls.authenticationStrength.displayName } },
            @{ n = "IncludedApps"; e = { ($_.conditions.applications.includeApplications | ForEach-Object { Resolve-App -AppId $_ }) -join ";" } },
            @{ n = "ExcludedApps"; e = { ($_.conditions.applications.excludeApplications | ForEach-Object { Resolve-App -AppId $_ }) -join ";" } },
            @{ n = "UserActions"; e = { $_.conditions.applications.includeUserActions -join ";" } },
            @{ n = "IncludePlatforms"; e = { $_.conditions.platforms.includePlatforms -join ";" } },
            @{ n = "ExcludePlatforms"; e = { $_.conditions.platforms.excludePlatforms -join ";" } },
            @{ n = "IncludeLocations"; e = { $_.conditions.locations.includeLocations -join ";" } },
            @{ n = "ExcludeLocations"; e = { $_.conditions.locations.excludeLocations -join ";" } },
            @{ n = "ClientAppTypes"; e = { $_.conditions.clientAppTypes -join ";" } },
            @{ n = "SignInRisk"; e = { $_.conditions.signInRiskLevels -join ";" } },
            @{ n = "UserRisk"; e = { $_.conditions.userRiskLevels -join ";" } },
            @{ n = "DeviceFilter"; e = { $_.conditions.devices.deviceFilter.rule } },
            @{ n = "SignInFrequency"; e = { if ($_.sessionControls.signInFrequency.isEnabled) { "$($_.sessionControls.signInFrequency.value) $($_.sessionControls.signInFrequency.type) $($_.sessionControls.signInFrequency.frequencyInterval)" } } },
            @{ n = "PersistentBrowser"; e = { $_.sessionControls.persistentBrowser.mode } },
            @{ n = "AppEnforcedRestrictions"; e = { $_.sessionControls.applicationEnforcedRestrictions.isEnabled } },
            @{ n = "CloudAppSecurity"; e = { $_.sessionControls.cloudAppSecurity.cloudAppSecurityType } },
            @{ n = "DisableResilienceDefaults"; e = { $_.sessionControls.disableResilienceDefaults } },
            @{ n = "TokenProtection"; e = { $_.sessionControls.secureSignInSession.isEnabled } },
            modifiedDateTime
    }
}

Connect-Cloud -Scopes "Policy.Read.All", "Directory.Read.All", "Application.Read.All"

$appNames = @{}
$groupCounts = @{}
$roleCounts = @{}
$objectNames = @{}
$totalUsers = Get-Count -Uri "$script:Graph/users/`$count?`$filter=accountEnabled eq true and userType eq 'Member'"
$totalGuests = Get-Count -Uri "$script:Graph/users/`$count?`$filter=userType eq 'Guest'"
$file = Join-Path $Path "conditional_access_policy_report.csv"
$policies = "$script:Graph/identity/conditionalAccess/policies" | Get-GraphPage
$policies | Format-Policy | Export-Csv $file -NoTypeInformation
if ($BackupJson) {
    $folder = New-Item -ItemType Directory -Path (Join-Path $Path "CA_Policies_$(Get-Date -Format yyyy-MM-dd)") -Force
    $policies | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | Out-File (Join-Path $folder "$($_.displayName -replace '[\\/:*?"<>|]', '_').json") }
    Write-Host "JSON backup: $folder"
}
Write-Host "Members: $totalUsers Guests: $totalGuests. Results: $file"
