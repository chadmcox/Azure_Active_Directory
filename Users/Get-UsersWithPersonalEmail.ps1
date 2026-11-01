<#PSScriptInfo
.VERSION 2026.10
.GUID da20b63b-73dc-4522-a2be-f4bd32ffe4ac
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
Finds member users whose alternate email addresses (otherMails) are personal mailboxes such as Gmail, Outlook.com or Yahoo, which can be used for password reset.
url: user resource type (otherMails) - https://learn.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Lists users with personal alternate email addresses.
.DESCRIPTION
    Replaces Security\findAADUsersPersonalAltEmail.
.PARAMETER Pattern
    Regex of personal email providers to match.
.EXAMPLE
    .\Get-UsersWithPersonalEmail.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$Pattern = "gmail|googlemail|hotmail|msn|outlook\.com|live\.|ymail|yahoo|aol|icloud|me\.com|proton|cox\.net|cox\.com|verizon\.net|att\.net|comcast\.net|wanadoo|orange",
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

$file = Join-Path $Path "entra_users_personal_alternate_email.csv"
"$script:Graph/users?`$filter=userType eq 'Member'&`$select=id,displayName,userPrincipalName,otherMails" | Get-GraphPage |
    Where-Object { $_.otherMails -match $Pattern } |
    Select-Object id, displayName, userPrincipalName, @{ n = "OtherMails"; e = { $_.otherMails -join ";" } } |
    Export-Csv $file -NoTypeInformation
Write-Host "Results: $file"
