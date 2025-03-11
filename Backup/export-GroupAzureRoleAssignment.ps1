#Requires -modules AzureADPreview,AZ
<#PSScriptInfo
.VERSION 2021.4.8
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
.TAGS 
.DESCRIPTION 
 
#>
param($defaultpath = ".")
cd $defaultpath
connect-azuread
Get-AzSubscription -pv sub | set-azcontext | foreach{
    write-host "Enumerating: $($sub.name)"
    Get-AzRoleAssignment -IncludeClassicAdministrators -pv assignment | foreach{
        foreach($rn in ($assignment.RoleDefinitionName -split ";")){
            $_ | select @{Name="Scope";Expression={$assignment.Scope}}, `
                @{Name="ScopeType";Expression={($assignment.Scope -split "/")[-2]}}, `
                @{Name="RoleDefinitionName";Expression={$rn}}, `
                @{Name="RoleDefinitionId";Expression={$assignment.RoleDefinitionId}}, `
                @{Name="DisplayName";Expression={$assignment.DisplayName}}, `
                @{Name="SignInName";Expression={$assignment.SignInName}}, `
                @{Name="ObjectID";Expression={$assignment.ObjectID}}, `
                @{Name="ObjectType";Expression={$assignment.Objecttype}}, `
                @{Name="Subscription";Expression={"$($sub.name) - ($sub.id)"}}
        }
    } 
} | export-csv "$defaultpath\Azure_Role_Assignment_$((Get-AzureADTenantDetail).DisplayName)_$(get-date -f yyyy-MM-dd).csv" -NoTypeInformation
