<#PSScriptInfo
.VERSION 2026.10
.GUID 74f7205c-21ff-4c0d-a51b-505e3374f42b
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
Shows how each enterprise app is assigned: whether assignment is required, how many users and groups are assigned directly, and whether broad groups like All Users are used, so apps assigned to individuals can be moved to groups.
url: Assign users and groups to an application - https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal
#>
<#
.SYNOPSIS
    Exports a summary of user and group assignments for every enterprise app.
.DESCRIPTION
    The operations guide recommends assigning apps to groups, not individual users. Apps that don't
    require assignment let anyone in the tenant (including guests) sign in. Microsoft first-party and
    agent apps are left out.
.EXAMPLE
    .\Get-AppAssignments.ps1 -Environment Global
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

function Format-App {
    param([Parameter(ValueFromPipeline)]$App)
    process {
        $assignments = @("$script:Graph/servicePrincipals/$($App.id)/appRoleAssignedTo?`$top=999" | Get-GraphPage)
        $users = @($assignments | Where-Object { $_.principalType -eq "User" })
        $groups = @($assignments | Where-Object { $_.principalType -eq "Group" })
        $App | Select-Object id, appId, displayName, preferredSingleSignOnMode, appRoleAssignmentRequired,
            @{ n = "UsersAssigned"; e = { $users.Count } },
            @{ n = "GroupsAssigned"; e = { $groups.Count } },
            @{ n = "BroadGroups"; e = { ($groups | Where-Object { $_.principalDisplayName -match "all users|everyone|all employees|all company" } | Select-Object -ExpandProperty principalDisplayName) -join ";" } },
            @{ n = "Finding"; e = {
                if (-not $_.appRoleAssignmentRequired) { "Assignment not required - anyone can sign in" }
                elseif ($users.Count -gt 0 -and $groups.Count -eq 0) { "Assigned to individual users only" }
                elseif ($users.Count -gt 0) { "Mix of users and groups" }
                elseif ($groups.Count -eq 0) { "Nobody assigned" }
                else { "Groups only" } } }
    }
}

Connect-Cloud -Scopes "Application.Read.All", "Directory.Read.All"

# Microsoft's public first-party app tenant, used to leave out Microsoft's own apps.
$microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
$file = Join-Path $Path "entra_app_assignments.csv"
Write-Host "Reading enterprise apps and their assignments"
"$script:Graph/servicePrincipals?`$filter=servicePrincipalType eq 'Application' and accountEnabled eq true&`$select=id,appId,displayName,appOwnerOrganizationId,preferredSingleSignOnMode,appRoleAssignmentRequired" |
    Get-GraphPage | Where-Object { $_.appOwnerOrganizationId -ne $microsoftTenantId -and $_.'@odata.type' -notmatch 'agent' } |
    Format-App | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
