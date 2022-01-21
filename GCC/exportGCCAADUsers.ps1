#requires -modules microsoft.graph.authentication
#requires -version 5
<#PSScriptInfo
.VERSION 2022.1.21
.GUID 368e7248-347a-46d9-ca35-3ae42890daed
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
.DESCRIPTION
this script will connect to a GCC High Tenant and retrieve all users
#>
cd $env:USERPROFILE
connect-mggraph -scopes "User.ReadBasic.All", "User.Read.All", "Directory.Read.All", "Directory.AccessAsUser.All", "AuditLog.Read.All" -Environment USGov

function list-AllAADUsers{
    [cmdletbinding()]
    param($uri)
do{
            $results = $null
            $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
            $results.value 
            $uri=$null;$uri = $Results.'@odata.nextlink'
        }until (($uri -eq $null))
}

$uri = "https://graph.microsoft.us/beta/users?`$select=displayName,signInActivity,userPrincipalName,userType,onPremisesSyncEnabled,creationType,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,onPremisesLastSyncDateTime,passwordPolicies,jobTitle"
list-AllAADUsers -uri $uri | select displayName,userPrincipalName,userType,creationType,Mail,accountEnabled,onPremisesSyncEnabled, `
    @{Name="lastSignInDateTime";Expression={try{$_.signInActivity.lastSignInDateTime}catch{}}},passwordPolicies, `
    lastPasswordChangeDateTime,onPremisesLastSyncDateTime,createdDateTime,jobTitle | export-csv "$env:USERPROFILE\export_aad_users.csv" -notypeinformation
