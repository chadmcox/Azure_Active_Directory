<#PSScriptInfo
.VERSION 2026.10
.GUID 8580e442-6a53-44cc-b821-2fe2d7fda178
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
Uploads hardware OATH tokens to Entra ID, one at a time or in bulk from a CSV, and can assign each token to a user.
url: How to manage hardware OATH tokens in Microsoft Entra ID - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens
#>
<#
.SYNOPSIS
    Uploads hardware OATH tokens.
.DESCRIPTION
    Replaces Hardware Oath Token\upload-HardwareOathToken. The CSV needs these headers:
    upn,serial number,secret key,time interval,manufacturer,model
    upn is only needed to assign the token to a user. Without -CsvPath the script asks for one token.
.EXAMPLE
    .\Add-HardwareOathTokens.ps1 -Environment Global -CsvPath .\Sample_Seed_Record_Template.csv
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$CsvPath
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

function Read-Token {
    Read-Host "Serial number" | Select-Object @{ n = "serial number"; e = { $_ } },
        @{ n = "manufacturer"; e = { Read-Host "Manufacturer" } },
        @{ n = "model"; e = { Read-Host "Model" } },
        @{ n = "secret key"; e = { Read-Host "Secret key" } },
        @{ n = "time interval"; e = { Read-Host "Time interval in seconds (usually 30)" } },
        @{ n = "upn"; e = { Read-Host "UPN to assign to (leave blank to not assign)" } }
}

function Add-Token {
    param([Parameter(ValueFromPipeline)]$Token)
    process {
        $body = @{
            serialNumber          = $Token."serial number"
            manufacturer          = $Token.manufacturer
            model                 = $Token.model
            secretKey             = $Token."secret key"
            timeIntervalInSeconds = [int]$Token."time interval"
        }
        if ($Token.upn) { $body.assignTo = @{ id = (Invoke-MgGraphRequest -Uri "$script:Graph/users/$($Token.upn)?`$select=id" -OutputType PSObject).id } }
        Write-Host "Uploading token $($Token.'serial number') $(if ($Token.upn) { "for $($Token.upn)" })"
        Invoke-MgGraphRequest -Uri "$script:Graph/directory/authenticationMethodDevices/hardwareOathDevices" -Method POST -Body ($body | ConvertTo-Json) -ContentType "application/json" -OutputType PSObject |
            Select-Object id, serialNumber, manufacturer, model, status, @{ n = "AssignedTo"; e = { $Token.upn } }
    }
}

Connect-Cloud -Scopes "Policy.ReadWrite.AuthenticationMethod", "UserAuthenticationMethod.ReadWrite.All", "User.Read.All"

$tokens = if ($CsvPath) { Import-Csv $CsvPath } else { Read-Token }
$tokens | Add-Token | Format-Table -AutoSize
