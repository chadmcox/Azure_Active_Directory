#Requires -module AzureADPreview
<#PSScriptInfo

.VERSION 2019.7.12

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
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_InactiveRoleMembers_$(get-date -f yyyy-MM-dd-HH-mm).csv"
connect-azuread

Get-AzureADDirectoryRole -PipelineVariable role | `
    where {$_.DisplayName -like "*Administrator" -and $_.DisplayName `
        -ne "Service Support Administrator"} | `
        Get-AzureADDirectoryRoleMember -PipelineVariable rolemem | `
            where -filterscript {!(Get-AzureADAuditDirectoryLogs -Filter "initiatedBy/user/userPrincipalName eq 
                '$($rolemem.userprincipalname)'" -all $true)} | select `
                    @{N="RoleDisplayname";E={$role.Displayname}}, `
                    @{N="ObjectID";E={$rolemem.objectid}}, `
                    @{N="UserPrincipalName";E={$rolemem.userprincipalname}} | export-csv $report -notypeinformation
                   
 write-host "Results can be found here: $report"
