#requires -modules msonline,azureadpreview
#requires -version 4
<#PSScriptInfo

.VERSION 2019.6.19

.GUID 368e7248-347a-46d9-ba35-3ae42890daed

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
#>
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\AAD_MemberlessUnifiedGroups_$((Get-AzureADTenantDetail).DisplayName)_$(get-date -f yyyy-MM-dd-HH-mm).csv"
write-host "Do not use this to find groups to delete outside of office 365.  do not delete directory in Azure AD"
write-host "Depending on the size of the environment this script will take a while to run"
#only prompt for connection if needed
try{Get-AzureADCurrentSessionInfo}
catch{Connect-azuread}
#retrieve list of groups from azure ad
$azureadgroups = get-azureadmsgroup -all $true | select DisplayName, Mailenabled,Mail,SecurityEnabled, `
        OnPremisesSyncEnabled,CreatedDateTime,visibility, `
        @{Name="DynamicMembership";Expression={if($_.GroupTypes -contains "DynamicMembership"){$true}else{$false}}}, `
        @{Name="Unified";Expression={if($_.GroupTypes -contains "Unified"){$true}else{$false}}}, `
        @{Name="ObjectId";Expression={$_.id}} | where {$_.unified -eq $true}

#filter out groups with no memberships
$azureadgroups | where -filterscript {!(Get-AzureADGroupMember -objectid $_.objectid -top 1)} | `
  export-csv $results -NoTypeInformation
