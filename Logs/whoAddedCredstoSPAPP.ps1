#Requires -Module azureadpreview
<#PSScriptInfo
.VERSION 2020.5.18
.GUID 816595ab-d7e2-410a-afa9-e2be1b3c4be6
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
.TAGS Get-msolRole Get-MsolRoleMember
.DESCRIPTION 
 here is the issue, I dont get a guid of the credential, the operation has to rewrite the creds so I end up retrieving all the creds

#> 
Param($resultsfile = "$env:TEMP\whocreatedcreds.csv")

function returnaadappcreds{
    param($objectid)
    try{Get-AzureADApplicationKeyCredential -objectid $objectid}catch{}
    try{Get-AzureADApplicationPasswordCredential -objectid $objectid}catch{}
    try{Get-AzureADServicePrincipalPasswordCredential -ObjectId $objectid}catch{}
    try{Get-AzureADServicePrincipalKeyCredential -ObjectId $objectid}catch{}
}


function retrieve-credexpiration{
    param($newvalue,$objectid,$date)
    write-host "objectid $($objectid)"
    #write-host "string $($newvalue)"
    $guids = @()
    $result = $newvalue -split('","') | foreach {$_-match "([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}){1}" ;
    $guids += $matches[0]
    }
    $foundcred = returnaadappcreds -objectid $objectid
    
    if($foundcred){
        ($foundcred | where {$_.keyid -in $guids}).enddate
    }else{
        write-host "nothing)"
    }
}
$aadlogon = Get-AzureADTenantDetail

if(!($aadlogon)){
    connect-azuread
}

$matches = $null
Get-AzureADAuditDirectoryLogs -Filter "Category eq 'ApplicationManagement'" -all $true | where {$_.activityDisplayName -in "Add service principal credentials","Update application – Certificates and secrets management","Update external secrets"} | select `
    ActivityDateTime,ActivityDisplayName,@{Name="ModifiedBy";Expression={$_.InitiatedBy.user.UserPrincipalName}}, `
    @{Name="ID";Expression={$_.TargetResources.ID}}, `
    @{Name="Displayname";Expression={$_.TargetResources.displayname}}, `
    @{Name="type";Expression={$_.TargetResources.type}}, `
    @{Name="CredEndDate";Expression={retrieve-credexpiration -newvalue $_.TargetResources.ModifiedProperties.newvalue -objectid $_.TargetResources.ID -date $_.ActivityDateTime}} | `
        export-csv $resultsfile -NoTypeInformation


write-host "Results can be found here $resultsfile" -ForegroundColor Yellow

<#(Get-AzureADAuditDirectoryLogs -Filter "Category eq 'ApplicationManagement'" -all $true | where {$_.activityDisplayName -in "Add service principal credentials","Update application – Certificates and secrets management","Update external secrets"}).TargetResources.ModifiedProperties.newvalue -split('","') | foreach {$_-match "([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}){1}" ;$matches[0]}


"KeyIdentifier=8ed1090d-bb55-4e3a-a6e0-c3981f3924a7" -match "([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}){1}"
(Get-AzureADAuditDirectoryLogs -Filter "Category eq 'ApplicationManagement'" -all $true | where {$_.activityDisplayName -in "Add service principal credentials","Update application – Certificates and secrets management","Update external secrets"}).TargetResources.ModifiedProperties.newvalue
#>




