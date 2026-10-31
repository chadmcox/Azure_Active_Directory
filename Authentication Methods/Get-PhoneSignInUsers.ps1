<#PSScriptInfo
.VERSION 2026.10
.GUID 5f07f7e7-8a3c-44bb-a736-7ea924167b02
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
Lists users who have a phone number set as a sign-in identity (identities issuer "phone").
url: objectIdentity resource type - https://learn.microsoft.com/en-us/graph/api/resources/objectidentity?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports users with a phone sign-in identity.
.DESCRIPTION
    Replaces MFA\Get-PhoneIssuer.
.EXAMPLE
    .\Get-PhoneSignInUsers.ps1 -Environment Global
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

Connect-Cloud -Scopes "User.Read.All"

$file = Join-Path $Path "entra_users_phone_identity.csv"
"$script:Graph/users?`$select=id,displayName,userPrincipalName,identities&`$filter=identities/any(x:x/issuer eq 'phone')" | Get-GraphPage -Eventual |
    ForEach-Object {
        $user = $_
        $user.identities | Where-Object { $_.issuer -eq "phone" } |
            Select-Object @{ n = "id"; e = { $user.id } }, @{ n = "displayName"; e = { $user.displayName } },
                @{ n = "userPrincipalName"; e = { $user.userPrincipalName } }, signInType, issuer, issuerAssignedId
    } | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
