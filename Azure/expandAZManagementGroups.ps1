<#PSScriptInfo

.VERSION 2020.11.20

.GUID 1be4febf-db79-4b83-9e81-ab88b4dda0c8

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

.TAGS Get-AzureRmContext Set-AzureRmContext Get-AzureRmRoleAssignment get-msoluser

.DESCRIPTION 
 This script is going to create a relationship csv for all of the management groups and subscriptions

#> 
Param($path="$env:userprofile\downloads")
write-host "Need to connect to Azure and Azure AD"
Connect-AzAccount
#Connect-AzureAD

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

function expandAzMG{
    [cmdletbinding()]
    param($name)
    write-information "Expanding Azure Manageent Group $name"
    Get-AzManagementGroup -GroupName $name -Expand -pv mg | select -ExpandProperty Children | foreach{
        $_ | select @{N="Parent";E={$mg.displayname}},@{N="Parentid";E={$mg.id}},@{N="Child";E={$_.displayname}},@{N="Childid";E={$_.id}},@{N="ChildType";E={$_.type}}
        if($_.type -eq "/providers/Microsoft.Management/managementGroups"){
            expandAzMG -name $_.name
        }
    }
}


expandAzMG -name (Get-AzureADTenantDetail).objectid | export-csv "$path\az_parent_child_relationships.csv" -notypeinformation
