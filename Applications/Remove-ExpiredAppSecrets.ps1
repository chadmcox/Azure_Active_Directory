<#PSScriptInfo
.VERSION 2026.10
.GUID e602fcec-5905-4031-9446-984290ba0f27
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
Removes client secrets that expired more than a set number of days ago from app registrations and service principals. Runs interactively or as an Azure Automation runbook with a managed identity.
url: application: removePassword - https://learn.microsoft.com/en-us/graph/api/application-removepassword?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Removes expired client secrets.
.DESCRIPTION
    Module-based version of Maintenance Task\runbook-removeAADExpiredCredentials. Only secrets are removed. Expired
    certificates are written to the report but left in place, because removing a certificate needs
    proof of possession of the current key.
.PARAMETER ExpiredForDays
    Only remove secrets that expired at least this many days ago. Default 30.
.PARAMETER MaxRemovals
    Stop after this many removals, as a safety limit. Default 3.
.PARAMETER Identity
    Sign in with the managed identity (Azure Automation). Pass -Environment too.
.EXAMPLE
    .\Remove-ExpiredAppSecrets.ps1 -Environment Global -WhatIf
.EXAMPLE
    .\Remove-ExpiredAppSecrets.ps1 -Environment Global -Identity -MaxRemovals 20
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [int]$ExpiredForDays = 30,
    [int]$MaxRemovals = 3,
    [switch]$Identity,
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

function Get-ExpiredCredentials {
    param([Parameter(ValueFromPipeline)]$Object)
    process {
        $owner = $Object
        @(
            $owner.passwordCredentials | Select-Object *, @{ n = "CredentialType"; e = { "Secret" } }
            $owner.keyCredentials | Select-Object *, @{ n = "CredentialType"; e = { "Certificate" } }
        ) | Where-Object { $_ -and [datetime]$_.endDateTime -lt (Get-Date).AddDays(-$ExpiredForDays) } |
            Select-Object @{ n = "Collection"; e = { $owner.Collection } },
                @{ n = "ObjectId"; e = { $owner.id } },
                @{ n = "DisplayName"; e = { $owner.displayName } },
                CredentialType, keyId, endDateTime
    }
}

function Remove-Secret {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromPipeline)]$Credential)
    process {
        $action = if ($Credential.CredentialType -ne "Secret") { "ReportOnly" }
            elseif ($PSCmdlet.ShouldProcess("$($Credential.DisplayName) secret $($Credential.keyId)", "Remove")) {
                $body = @{ keyId = $Credential.keyId } | ConvertTo-Json
                Invoke-MgGraphRequest -Uri "$script:Graph/$($Credential.Collection)/$($Credential.ObjectId)/removePassword" -Method POST -Body $body -ContentType "application/json"
                "Removed"
            } else { "WhatIf" }
        $Credential | Select-Object *, @{ n = "Action"; e = { $action } }
    }
}

Connect-Cloud -Scopes "Application.ReadWrite.All" -Identity:$Identity

$expired = @(
    "$script:Graph/applications?`$select=id,displayName,keyCredentials,passwordCredentials" | Get-GraphPage |
        Select-Object *, @{ n = "Collection"; e = { "applications" } }
    "$script:Graph/servicePrincipals?`$filter=servicePrincipalType ne 'ManagedIdentity'&`$select=id,displayName,keyCredentials,passwordCredentials" | Get-GraphPage |
        Select-Object *, @{ n = "Collection"; e = { "servicePrincipals" } }
) | Get-ExpiredCredentials

$results = @(
    $expired | Where-Object { $_.CredentialType -eq "Secret" } | Select-Object -First $MaxRemovals | Remove-Secret
    $expired | Where-Object { $_.CredentialType -ne "Secret" } | Remove-Secret
)
$results | Format-Table DisplayName, CredentialType, endDateTime, Action -AutoSize | Out-String | Write-Output
if (-not $Identity) {
    $file = Join-Path $Path "entra_expired_credentials_removed.csv"
    $results | Export-Csv $file -NoTypeInformation -WhatIf:$false
    Write-Host "Results: $file"
}
