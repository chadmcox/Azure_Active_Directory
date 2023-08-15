#Requires -module azureadpreview
<#PSScriptInfo
.VERSION 2020.8.18
.GUID 5e7bfd30-88b8-4f4d-99fd-c4ffbfcf5be6
.AUTHOR Chad.Cox@microsoft.com
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
.RELEASENOTES
.DESCRIPTION
This script will pull in Hybrid devices that are disabled in Azure AD, that are still being used by users and failing to authenticate.
#>
connect-azuread

#this will list devices that are still being used but are disabled
Get-AzureADAuditSignInLogs -filter "appDisplayName eq 'Microsoft Office' and status/errorCode eq 135011" -all $true | select `
    UserPrincipalName,AppDisplayName, @{Name="DeviceName";Expression={$_.DeviceDetail.DisplayName}}, `
    @{Name="ErrorCode";Expression={$_.Status.errorcode}}, @{Name="FailureReason";Expression={$_.Status.FailureReason}} -Unique | `
        export-csv .\aad_device_still_used_but_disabled.csv


Get-AzureADAuditSignInLogs -filter "status/errorCode eq 135011" -all $true | select `
    UserPrincipalName,AppDisplayName, @{Name="DeviceName";Expression={$_.DeviceDetail.DisplayName}}, `
    @{Name="ErrorCode";Expression={$_.Status.errorcode}}, @{Name="FailureReason";Expression={$_.Status.FailureReason}} -Unique | `
        export-csv .\aad_device_still_used_but_disabled.csv
