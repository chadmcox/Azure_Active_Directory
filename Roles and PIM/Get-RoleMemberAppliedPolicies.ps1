<#PSScriptInfo
.VERSION 2026.10
.GUID 5881bf12-d1ba-4c44-aec3-5f87eec1fec0
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
Shows which Conditional Access policies were applied to the sign-ins of privileged role members, to spot admins who are not covered.
url: List signIns - https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Lists Conditional Access policies applied to privileged role member sign-ins.
.DESCRIPTION
    Replaces Roles\getAADRoleCAPused.
.PARAMETER Days
    How many days of sign-ins to read. Default 7.
.EXAMPLE
    .\Get-RoleMemberAppliedPolicies.ps1 -Environment Global -Days 14
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

function Get-AppliedPolicies {
    param([Parameter(ValueFromPipeline)]$Admin)
    process {
        "$script:Graph/auditLogs/signIns?`$filter=userId eq '$($Admin.id)' and createdDateTime ge $since" | Get-GraphPage | ForEach-Object {
            $signIn = $_
            $signIn.appliedConditionalAccessPolicies | Where-Object { $_.result -in "success", "failure" } |
                Select-Object @{ n = "UserPrincipalName"; e = { $Admin.userPrincipalName } },
                    @{ n = "Roles"; e = { $Admin.Roles } },
                    @{ n = "Policy"; e = { $_.displayName } },
                    @{ n = "Result"; e = { $_.result } },
                    @{ n = "App"; e = { $signIn.appDisplayName } }
        }
    }
}

Connect-Cloud -Scopes "AuditLog.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$file = Join-Path $Path "entra_role_member_applied_policies.csv"
"$script:Graph/roleManagement/directory/roleAssignments?`$expand=principal,roleDefinition" | Get-GraphPage |
    Where-Object { $_.roleDefinition.isPrivileged -and $_.principal.'@odata.type' -eq "#microsoft.graph.user" } |
    Group-Object { $_.principal.id } |
    Select-Object @{ n = "id"; e = { $_.Name } },
        @{ n = "userPrincipalName"; e = { $_.Group[0].principal.userPrincipalName } },
        @{ n = "Roles"; e = { ($_.Group.roleDefinition.displayName | Sort-Object -Unique) -join ";" } } |
    Get-AppliedPolicies |
    Group-Object UserPrincipalName, Policy, Result |
    Select-Object @{ n = "UserPrincipalName"; e = { $_.Group[0].UserPrincipalName } },
        @{ n = "Roles"; e = { $_.Group[0].Roles } },
        @{ n = "Policy"; e = { $_.Group[0].Policy } },
        @{ n = "Result"; e = { $_.Group[0].Result } },
        @{ n = "SignIns"; e = { $_.Count } },
        @{ n = "Apps"; e = { ($_.Group.App | Sort-Object -Unique) -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
