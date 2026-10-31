<#PSScriptInfo
.VERSION 2026.10
.GUID ecbecb07-c334-48df-85b9-2b0d4e892180
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
Activates a hardware OATH token that is assigned to a user, using a code shown on the token.
url: How to manage hardware OATH tokens in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens
#>
<#
.SYNOPSIS
    Activates a user's hardware OATH token.
.DESCRIPTION
    Replaces Hardware Oath Token\activate-UserHardwareOathToken. Lists the user's tokens, then asks
    which one to activate and for the code on the token.
.EXAMPLE
    .\Enable-HardwareOathToken.ps1 -Environment Global -UserPrincipalName "<person UPN>"
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [Parameter(Mandatory)][string]$UserPrincipalName
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

function Get-UserTokens {
    param([string]$UserId)
    "$script:Graph/users/$UserId/authentication/hardwareOathMethods" | Get-GraphPage | ForEach-Object {
        Invoke-MgGraphRequest -Uri "$script:Graph/directory/authenticationMethodDevices/hardwareOathDevices/$($_.id)" -OutputType PSObject |
            Select-Object id, serialNumber, manufacturer, model, status
    }
}

Connect-Cloud -Scopes "UserAuthenticationMethod.ReadWrite.All", "Policy.ReadWrite.AuthenticationMethod", "User.Read.All"

$userId = (Invoke-MgGraphRequest -Uri "$script:Graph/users/$($UserPrincipalName)?`$select=id" -OutputType PSObject).id
Get-UserTokens -UserId $userId | Format-Table -AutoSize | Out-Host
$tokenId = Read-Host "Paste the id of the token to activate"
$code = Read-Host "Type the code shown on the token"
$body = @{ verificationCode = $code } | ConvertTo-Json
Invoke-MgGraphRequest -Uri "$script:Graph/users/$userId/authentication/hardwareOathMethods/$tokenId/activate" -Method POST -Body $body -ContentType "application/json"
Start-Sleep -Seconds 3
Get-UserTokens -UserId $userId | Format-Table -AutoSize
