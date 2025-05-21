#Requires -module AzureADPreview, msonline
<#PSScriptInfo

.VERSION 2019.7.15

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
this script looks for conditional access policies being applied to memers of aad roles.
Ideally we would look for things like "Baseline policy: Require MFA for admins" being used

#>

param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_RoleMember_Conditional_Access_Applied_Policies_$(get-date -f yyyy-MM-dd-HH-mm).csv"

$results = Get-AzureADDirectoryRole -PipelineVariable role | 
    where {$_.DisplayName -like "*Administrator" -and $_.DisplayName -ne "Service Support Administrator"} | `
        Get-AzureADDirectoryRoleMember -PipelineVariable rolemem | foreach{
            Get-AzureADAuditSignInLogs -Filter "userPrincipalName eq '$($rolemem.userprincipalname)'" -all $true -PipelineVariable aadsignin | `
                where ConditionalAccessStatus -eq 'Success' | select -ExpandProperty AppliedConditionalAccessPolicies | foreach{
                    $capdn = $_
                    $aadsignin | select UserPrincipalname, ConditionalAccessStatus, `
                    @{N="ConditionalAccessDisplayname";E={$capdn.displayname}}, `
                    @{N="AuthMethod";E={$_.mfadetail.authmethod}}
                }
        }

$results | select * -Unique | export-csv $report -notypeinformation
