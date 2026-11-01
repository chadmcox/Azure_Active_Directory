<#PSScriptInfo
.VERSION 2026.10
.GUID dd68ce9d-4354-40f4-b5f0-a1dee7f11add
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
Finds the users, groups and apps that can add credentials to apps: apps granted Application.ReadWrite.All, members of the directory roles that allow it, and the owners of those apps.
url: Privileged roles and permissions in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/privileged-roles-permissions
#>
<#
.SYNOPSIS
    Lists who can add credentials to apps.
.DESCRIPTION
    Replaces Get-AADObjectsCanChangeCred and Roles\AzureADModule\roleAbleToAddCredentials.
.EXAMPLE
    .\Get-PrincipalsThatCanChangeCredentials.ps1 -Environment Global
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
    ChangeCredentials     = @{
        Permissions = "Application.ReadWrite.All", "Application.ReadWrite.OwnedBy"
        Roles       = "62e90394-69f5-4237-9190-012177145e10", "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", "158c047a-c907-4556-b7ef-446551a6b5f7",
                      "d29b2b05-8046-44ba-8758-1e26182fcf32", "4ba39ca4-527c-499a-b93d-d9b492c50246", "c4e39bd9-1100-46d3-8c65-fb160da0071f",
                      "7be44c8a-adaf-4e2a-84d6-ab2649e08a13"
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
$names = "ChangeCredentials"

$file = Join-Path $Path "entra_principalsthatcanchangecredentials.csv"
$names | Get-CapabilityPaths | Sort-Object Capability, displayName, Via -Unique | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
