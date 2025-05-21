#Requires -Module azureadpreview
<#PSScriptInfo

.VERSION 2019.7.10

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

#> 
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_ChangesbyGlobalAdmins_$(get-date -f yyyy-MM-dd-HH-mm).csv"
@(Get-AzureADDirectoryRole -PipelineVariable role | `
    where RoleTemplateId -eq '62e90394-69f5-4237-9190-012177145e10' | `
        Get-AzureADDirectoryRoleMember -PipelineVariable rolemem | foreach {
            Get-AzureADAuditDirectoryLogs -Filter "initiatedBy/user/userPrincipalName eq 
                '$($rolemem.userprincipalname)'" -all $true | select `
                    @{N="UserPrincipalName";E={$rolemem.userprincipalname}}, `
                    Category,LoggedByService,ActivityDisplayName -Unique
        }) | export-csv $report -notypeinformation
