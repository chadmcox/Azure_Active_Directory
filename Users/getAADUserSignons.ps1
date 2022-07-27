#requires -module Azureadpreview,msonline
<#PSScriptInfo

.VERSION 2019.7.10

.GUID e7a48d24-7c7a-4a21-b32d-2a86c844b90a

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

.TAGS 

.DETAILS

.EXAMPLE

#>
param($reportpath="$env:userprofile\Documents",$staledays=120)
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_UserSignons_$(get-date -f yyyy-MM-dd-HH-mm).csv"

function getaadlastazureadlogon{
param($upn)
    <#this functions checks to see if the objected has signed in over the last 30 days#>
    $last_signon_date = (Get-AzureADAuditSignInLogs -Filter "UserId eq '$upn'" -all $true | sort CreatedDateTime -Descending | select CreatedDateTime -first 1).CreatedDateTime
    write-host "$upn - $last_signon_date"
    if($last_signon_date){get-date $last_signon_date -Format MM/dd/yyyy}
}


write-host "Retrieving users from AzureAD"
get-azureaduser -all $true -pv user | foreach {
    $user | select objectid, UserPrincipalName, `
    @{N='LastSignOn';E={getaadlastazureadlogon -upn $_.objectid}}
} | export-csv $report -NoTypeInformation

write-host "Results can be found here: $report"
