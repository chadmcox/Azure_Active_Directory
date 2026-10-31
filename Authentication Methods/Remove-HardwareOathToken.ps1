<#PSScriptInfo
.VERSION 2026.10
.GUID 5b8a3a7d-76f2-42ab-a354-82e36f8e41fa
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
Removes a hardware OATH token from a user so it can be reassigned or retired.
url: Delete hardwareOathAuthenticationMethod - https://learn.microsoft.com/en-us/graph/api/hardwareoathauthenticationmethod-delete?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes a hardware OATH token from a user.
.DESCRIPTION
    Replaces Hardware Oath Token\delete-HardwareOathTokenFromUser (which called the wrong URL).
.EXAMPLE
    .\Remove-HardwareOathToken.ps1 -Environment Global -UserPrincipalName "<person UPN>"
#>
[CmdletBinding(SupportsShouldProcess)]
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
$tokenId = Read-Host "Paste the id of the token to remove"
if ($tokenId -and $PSCmdlet.ShouldProcess("$UserPrincipalName token $tokenId", "Remove")) {
    Invoke-MgGraphRequest -Uri "$script:Graph/users/$userId/authentication/hardwareOathMethods/$tokenId" -Method DELETE
    Start-Sleep -Seconds 3
    Get-UserTokens -UserId $userId | Format-Table -AutoSize
}
