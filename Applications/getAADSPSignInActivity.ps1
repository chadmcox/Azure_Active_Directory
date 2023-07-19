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
#>
param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

#modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.Reports,Microsoft.Graph.Beta.Users,Microsoft.Graph.Beta.Applications
$sps_lastsignin = Get-MgBetaReportServicePrincipalSignInActivity -all
$sps_lastsignin_hash = $sps_lastsignin | select appid -ExpandProperty LastSignInActivity | select appid, @{N="LastSignInDateTime";E={$_.LastSignInDateTime}} | group appid -AsHashTable -AsString

Get-MgBetaServicePrincipal -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -ExpandProperty owners | `
    where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts"} | select `
    id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
    @{N="Owner";E={($_.owners.id | foreach{Get-mgbetauser -userId $_}).UserPrincipalName -join(";")}}, `
    @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="LastSignInDateTime";E={[datetime]$sps_lastsignin_hash[$_.appid].LastSignInDateTime}} | export-csv .\aadsp_activity.csv -notypeinformation
