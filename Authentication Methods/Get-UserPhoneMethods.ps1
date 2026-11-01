<#PSScriptInfo
.VERSION 2026.10
.GUID 562f22cd-cb05-4187-a5e4-b3c4732b63fb
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
Lists every phone number registered for MFA or SSPR per user, with phone type and whether SMS sign-in is turned on.
url: List authentication methods - https://learn.microsoft.com/en-us/graph/api/authentication-list-methods?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports users' registered phone methods.
.DESCRIPTION
    Replaces get-phonemethods and get-SMSSignin. Only users with a phone registered are read.
.EXAMPLE
    .\Get-UserPhoneMethods.ps1 -Environment Global
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

function Get-Methods {
    param([Parameter(ValueFromPipeline)]$User)
    process {
        $u = $User
        $collection = "phoneMethods"
        "$script:Graph/users/$($u.id)/authentication/$collection" | Get-GraphPage |
            Where-Object { $_.'@odata.type' -ne "#microsoft.graph.passwordAuthenticationMethod" } |
            Select-Object @{ n = "UserId"; e = { $u.id } },
                @{ n = "UserPrincipalName"; e = { $u.userPrincipalName } },
                @{ n = "MethodType"; e = { if ($_.'@odata.type') { ($_.'@odata.type' -split "\.")[-1] } else { $collection } } },
                displayName, phoneNumber, phoneType, smsSignInState, deviceTag, phoneAppVersion, clientAppName, createdDateTime, lastUsedDateTime
    }
}

Connect-Cloud -Scopes "UserAuthenticationMethod.Read.All", "AuditLog.Read.All"

$filter = "?`$filter=methodsRegistered/any(m:m eq 'mobilePhone')"
$file = Join-Path $Path "entra_user_phone_methods.csv"
Write-Host "Getting users with registered methods"
"$script:Graph/reports/authenticationMethods/userRegistrationDetails$filter" | Get-GraphPage |
    Where-Object { $_.methodsRegistered } |
    Get-Methods | Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
