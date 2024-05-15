#Requires -Modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.Reports,Microsoft.Graph.Beta.Users,Microsoft.Graph.Beta.Applications
<#PSScriptInfo
.VERSION 2023.7
.GUID 368f7248-347a-46d9-ba36-3ae42890daed
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
from the use or distribution of the Sample 

.NOTE
This is a beta api make sure
https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta&tabs=http

This script will create a report of all enabled service principals and if they have any recent signin data.
#>
param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

#modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.Reports,Microsoft.Graph.Beta.Users,Microsoft.Graph.Beta.Applications
Write-host "Get all the service principals that have datetime populated"
$sps_lastsignin = Get-MgBetaReportServicePrincipalSignInActivity -all | where {$_.LastSignInActivity.LastSignInDateTime} | select appid, LastSignInActivity, `
        @{N="SignInActivityType";E={if($_.delegatedClientSignInActivity.lastSignInDateTime){"delegatedClient"
        }elseif($_.delegatedResourceSignInActivity.lastSignInDateTime){"delegatedResource"
        }elseif($_.applicationAuthenticationClientSignInActivity.lastSignInDateTime){"applicationAuthenticationClient"
        }elseif($_.applicationAuthenticationResourceSignInActivity.lastSignInDateTime){"applicationAuthenticationResource"
        }else{"unknown"}}}
write-host "Found SignInActivity for $($sps_lastsignin.count) service principals"
write-host "Build a hash table for quick lookup"
$sps_lastsignin_hash = $sps_lastsignin | select appid,signInActivityType -ExpandProperty LastSignInActivity | `
    select appid, @{N="LastSignInDateTime";E={$_.LastSignInDateTime}},signInActivityType | `
    group appid -AsHashTable -AsString

#preferredSingleSignOnMode

write-host "Getting all service principals and create the report"
Get-MgBetaServicePrincipal -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')} | select `
    id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname,AppRoleAssignmentRequired,SignInAudience,preferredSingleSignOnMode, `
    @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}}, `
    @{N="SignInActivityType";E={$sps_lastsignin_hash[$_.appid].SignInActivityType}}, `
    #@{N="OwnerId";E={($_.owners).id -join(";")}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | export-csv .\aadsp_activity.csv -notypeinformation

write-host "finished, results can be found here $($defaultdirectory)\aadsp_activity.csv"
