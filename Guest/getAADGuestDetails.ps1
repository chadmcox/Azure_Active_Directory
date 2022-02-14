#Requires -Module azureadpreview
<#PSScriptInfo

.VERSION 2019.7.26

.GUID efd0d932-eeb4-4454-859a-1ab19f84fc8f

.AUTHOR Chad.Cox@microsoft.com
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

.TAGS get-msoluser

.DESCRIPTION
    CIS Microsoft Azure Foundation
    https://azure.microsoft.com/mediahandler/files/resourcefiles/cis-microsoft-azure-foundations-security-benchmark/CIS_Microsoft_Azure_Foundations_Benchmark_v1.0.0.pdf

    Gathers all Guest Accounts in Azure AD Instance

    Azure AD is extended to include Azure AD B2B collaboration, allowing you to invite people from 
     outside your organization to be guest users in your cloud account. Until you have a business need 
     to provide guest access to any user, avoid creating such guest users. Guest users are typically 
     added out of your employee on-boarding/off-boarding process and could potentially be lying there 
     unnoticed indefinitely leading to a potential vulnerability.

    get-msoluser https://docs.microsoft.com/en-us/powershell/module/msonline/get-msoluser?view=azureadps-1.0

 

#> 
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\AAD_Guests_$((Get-AzureADTenantDetail).DisplayName)_$(get-date -f yyyy-MM-dd-HH-mm).csv"

function getaadlastazureadlogon{
param($id)
    <#this functions checks to see if the objected has signed in over the last 30 days#>
    $last_signon_date = (Get-AzureADAuditSignInLogs -Filter "UserId eq '$id'" -top 1).CreatedDateTime
    if($last_signon_date){get-date $last_signon_date -Format MM/dd/yyyy}
}

$AAD_Domains = (Get-AzureADDomain).name
$hash_MSA = @{Name="PossibleDupMSA";Expression={isMSAccount -upn ($guest).UserPrincipalName}}
$hash_pending = @{name='PendinginDays';
    expression={if($guest.UserState -eq "PendingAcceptance"){
        (new-TimeSpan($($guest.UserStateChangedOn)) $(Get-Date)).days}}}
$hash_lastsignon = @{N='LastSignOn';E={getaadlastazureadlogon -id $_.objectid}}

function isMSAccount{
    param($upn)
    foreach($aadd in $AAD_Domains){
        if(($upn -split "#")[0] -like "*_$aadd"){
            return $True ;exit
        }
    }
    $false
}

#this will take a while to run as all users are being retrieved
@(Get-AzureADUser -Filter "userType eq 'Guest'" -All $true -PipelineVariable guest | foreach{
        $guest | select objectid,UserPrincipalName, UserState, UserStateChangedOn,UserType,$hash_lastsignon, `
        AccountEnabled,$hash_MSA,$hash_pending
    }) | export-csv $report -notypeinformation
