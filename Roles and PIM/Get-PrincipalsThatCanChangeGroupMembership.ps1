<#PSScriptInfo
.VERSION 2026.10
.GUID d192fbae-a7b6-433a-8937-dc7529fe4968
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
Finds the users, groups and apps that can change the membership of any group: apps granted GroupMember.ReadWrite.All or Group.ReadWrite.All, members of the directory roles that allow it, and the owners of those apps.
url: Privileged roles and permissions in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/privileged-roles-permissions
#>
<#
.SYNOPSIS
    Lists who can change the membership of any group.
.DESCRIPTION
    Replaces Get-AADObjectsCanChangeGroupMembership, roleAbleToChangeGroupMembership and get-AppsandOwnersCanChangeAllGroupMembership.
.EXAMPLE
    .\Get-PrincipalsThatCanChangeGroupMembership.ps1 -Environment Global
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

# Well-known Microsoft Graph permissions and built-in role template IDs for each capability.
$capabilities = @{
    ChangeGroupMembership = @{
        Permissions = "GroupMember.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All"
        Roles       = "62e90394-69f5-4237-9190-012177145e10", "810a2642-a034-447f-a5e8-41beaa378541", "11451d60-acb2-45eb-a7d6-43d0f0125c13",
                      "45d8d3c5-c802-45c6-b32a-1d70b5e1e86e", "744ec460-397e-42ad-a462-8b3f9747a02c", "b5a8dcf3-09d5-43a9-a639-8e29ef291470",
                      "fdd7a751-b60b-444a-984c-02652fe8fa1c", "69091246-20e8-4a56-aa4d-066075b2a7a8", "f28a1f50-f6e7-4571-818b-6a12f2af6b6c",
                      "29232cdf-9323-42fd-ade2-1d097af3e4de", "9360feb5-f418-4baa-8175-e2a00bac4301", "fe930be7-5e62-47db-91af-98c3a49a38b1"
    }
}

function Get-AppOwners {
    param([Parameter(ValueFromPipeline)][string]$AppId, [string]$CapabilityName)
    process {
        "$script:Graph/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,displayName&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage |
            ForEach-Object { $sp = $_; $sp.owners | Select-Object @{ n = "Capability"; e = { $CapabilityName } }, displayName, userPrincipalName,
                @{ n = "Via"; e = { "Owner of service principal $($sp.displayName)" } } }
        "$script:Graph/applications?`$filter=appId eq '$AppId'&`$select=id,displayName&`$expand=owners(`$select=id,displayName,userPrincipalName)" | Get-GraphPage |
            ForEach-Object { $app = $_; $app.owners | Select-Object @{ n = "Capability"; e = { $CapabilityName } }, displayName, userPrincipalName,
                @{ n = "Via"; e = { "Owner of app registration $($app.displayName)" } } }
    }
}

function Get-CapabilityPaths {
    param([Parameter(ValueFromPipeline)][string]$CapabilityName)
    process {
        $definition = $capabilities[$CapabilityName]
        $roleIds = $graphSp.appRoles | Where-Object { $_.value -in $definition.Permissions } | Group-Object id -AsHashTable -AsString
        if (-not $roleIds) { $roleIds = @{} }
        $apps = "$script:Graph/servicePrincipals/$($graphSp.id)/appRoleAssignedTo" | Get-GraphPage |
            Where-Object { $_.appRoleId -and $roleIds.ContainsKey($_.appRoleId) } |
            Select-Object @{ n = "Capability"; e = { $CapabilityName } },
                @{ n = "displayName"; e = { $_.principalDisplayName } },
                @{ n = "userPrincipalName"; e = { $null } },
                @{ n = "Via"; e = { "Graph permission $($roleIds[$_.appRoleId].value)" } },
                @{ n = "AppId"; e = {
                    if (-not $appIds.ContainsKey($_.principalId)) { $appIds[$_.principalId] = (Invoke-MgGraphRequest -Uri "$script:Graph/servicePrincipals/$($_.principalId)?`$select=appId" -OutputType PSObject).appId }
                    $appIds[$_.principalId] } }
        $members = $definition.Roles | ForEach-Object {
            "$script:Graph/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$_'&`$expand=principal,roleDefinition" | Get-GraphPage
        } | Select-Object @{ n = "Capability"; e = { $CapabilityName } },
            @{ n = "displayName"; e = { $_.principal.displayName } },
            @{ n = "userPrincipalName"; e = { $_.principal.userPrincipalName } },
            @{ n = "Via"; e = { "Role $($_.roleDefinition.displayName)" } },
            @{ n = "AppId"; e = { $_.principal.appId } }
        @($apps; $members) | Select-Object Capability, displayName, userPrincipalName, Via
        @($apps; $members) | Where-Object { $_.AppId } | Select-Object -ExpandProperty AppId -Unique | Get-AppOwners -CapabilityName $CapabilityName
    }
}

Connect-Cloud -Scopes "Application.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All"

$appIds = @{}
$graphSp = "$script:Graph/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id,appRoles" | Get-GraphPage
$names = "ChangeGroupMembership"

$file = Join-Path $Path "entra_principalsthatcanchangegroupmembership.csv"
$names | Get-CapabilityPaths | Sort-Object Capability, displayName, Via -Unique | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
