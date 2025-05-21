<#PSScriptInfo
.VERSION 2021.10
.GUID 368f7248-347a-46d9-ba35-3ae42890daed
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

.Note
because the azuread modules do not handle time outs this script can be incomplete

#>

cd "$env:USERPROFILE\Downloads"

$application_service_principals = Get-AzureADServicePrincipal -Filter "serviceprincipaltype eq 'Application'" -All $true
$hash_splookup = $application_service_principals | select objectid, displayname | group objectid -AsHashTable -asstring
$application_service_principals | select -PipelineVariable aadsp | foreach{
    write-host "Exporting $($aadsp.displayname)"
    $aadsp | Get-AzureADServicePrincipalOAuth2PermissionGrant -all $true -PipelineVariable PERMGrant | select `
        @{Name="Principal";Expression={$AADSP.AppDisplayName}},@{Name="AccountEnabled";Expression={$AADSP.AccountEnabled}},`
        @{Name="PublisherName";Expression={$AADSP.PublisherName}}, ConsentType, ResourceId, Scope -Unique
} -PipelineVariable sp | foreach{
    $_.scope -split(" ") | select @{Name="Scope";Expression={$_}}, @{Name="Principal";Expression={$SP.Principal}}, `
        @{Name="AccountEnabled";Expression={$SP.AccountEnabled}}, @{Name="PublisherName";Expression={$SP.PublisherName}}, `
        @{Name="ConsentType";Expression={$SP.ConsentType}}, @{Name="API";Expression={$hash_splookup[$SP.ResourceId].displayname}}
} | export-csv .\appdelegatedperms.csv -NoTypeInformation

cls
write-host "Finished: one file is created here $("$env:USERPROFILE\Downloads")"
