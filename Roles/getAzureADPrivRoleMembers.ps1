#requires -module Azureadpreview,msonline
<#PSScriptInfo

.VERSION 2019.7.10

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
CIS Microsoft Azure Foundation
 https://azure.microsoft.com/mediahandler/files/resourcefiles/cis-microsoft-azure-foundations-security-benchmark/CIS_Microsoft_Azure_Foundations_Benchmark_v1.0.0.pdf
 1.1 Ensure that MFA authentication is enabled for all privileged users
    join ObjectID from these results to objectid of the allaadusersresults
    to get results of which privileged accounts is not leveraging MFA

.EXAMPLE

#>
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_PrivRoleMembers_$(get-date -f yyyy-MM-dd-HH-mm).csv"

function getConsentedApps{
    param($objectid)
    $consented = Get-AzureADUserOAuth2PermissionGrant -ObjectId $objectid -PipelineVariable grants | `
        select -ExpandProperty scope
    return [string]$consented
}

#region hash variables for calculated properties
$hash_priorityrole = @{Name="Tier";Expression={getPriorityLevel -guid $role.RoleTemplateId}}
$hash_userrole = @{Name="Role";Expression={$role.displayname}}
$hash_userroleid = @{Name="RoleID";Expression={$role.objectID}}
$hash_userroleteplateid = @{Name="RoleTemplateId";Expression={$role.RoleTemplateId}}
$hash_sppwdexpired = @{Name="ExpiredPWDCredentials";
    Expression={if($rolemem.passwordcredentials | where {$_.enddate -lt $todaysdate}){$true}else{$false}}}
$hash_spkeyexpired = @{Name="ExpiredKEYCredentials";
    Expression={if($rolemem.KeyCredentials | where {$_.enddate -lt $todaysdate}){$true}else{$false}}}
$hash_da = @{Name="Admin";Expression={if($adminGuids -contains $role.RoleTemplateId){$true}else{$false}}}
$hash_AgeinDays = @{Name="RefreshTokenAgeinDays";
        Expression={(new-TimeSpan($_.RefreshTokensValidFromDateTime) $(Get-Date)).days}}
$hash_AppConsents = @{Name="consentedScopes";
        Expression={getConsentedApps -objectid $_.ObjectID}}
$hash_lastsignon = @{name='LastSignOn';
    expression={getaadlastazureadlogon -upn $_.userprincipalname}}

#endregion

#region GUIDS
#easier to use guids.  Have to use the Role Template ID because they are the same between tenants
#level0guids is for Full control of sensitve key security controls for azure ad
$Level0Guids = "62e90394-69f5-4237-9190-012177145e10", ` #Company Administrator / Global Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814", ` #Privileged Role Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d", ` #Security Administrator
    "17315797-102d-40b4-93e0-432062caca18" #Compliance Administrator

#this is service admin roles for office 365 and other things
$Level1Guids = (get-azureaddirectoryroletemplate | where Displayname -like "*Service Administrator").objectid

$Level2Guids =  "729827e3-9c14-49f7-bb1b-9608f156bbb8", ` # Password Administrator / Helpdesk Administrator
                "fe930be7-5e62-47db-91af-98c3a49a38b1", ` #User Account Administrator
                "b0f54661-2d74-4c50-afa3-1ec803f12efe", #Billing Administrator
                "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9" #Conditional Access Administrator

$adminGuids = $Level0Guids + $Level1Guids + $Level2Guids
#endregion

function getaadlastazureadlogon{
param($upn)
    $last_signon_date = (Get-AzureADAuditSignInLogs -Filter "userPrincipalName eq '$upn'" -top 1).CreatedDateTime
    if($last_signon_date){get-date $last_signon_date -Format MM/dd/yyyy}
}

function getPriorityLevel{
    param($guid)
    if($Level0Guids -contains $guid){
        return "Critical"
    }elseif($Level1Guids -contains $guid){
        return "High"
    }Elseif($Level2Guids -contains $guid){
        return "Medium"
    }else{
        return "Low"
    }
}

Write-host "Retrieving Azure AD Privileged Role Members."
#query every role in use within Azure AD
$todaysdate = (get-date).DateTime
@(Get-AzureADDirectoryRole -PipelineVariable role | foreach{
    Write-host "Retrieving Role Members from: $($role.displayname)."
    Get-AzureADDirectoryRoleMember -objectid $_.objectid -PipelineVariable rolemem | select `
    $hash_userroleteplateid,$hash_userroleid,$hash_userrole,$hash_priorityrole,$hash_da,DisplayName, `
    UserPrincipalName,mail,ObjectID,objecttype,AccountEnabled,usertype,PublisherName,ServicePrincipalType, `
    $hash_sppwdexpired,$hash_spkeyexpired,RefreshTokensValidFromDateTime,$hash_AgeinDays,$hash_lastsignon, `
    PasswordPolicies,DirSyncEnabled,$hash_AppConsents | sort priorityrole,role}) | export-csv $report -notypeinformation

write-host "Report can be found here: $report" -ForegroundColor Yellow

$recommendation_report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_StalePrivRoleMembers_$(get-date -f yyyy-MM-dd-HH-mm).csv"
import-csv $report | where {$_.LastSignOn -eq "" -and  [int]$($_.RefreshTokenAgeinDays) -gt 120 `
    -and $_.ObjectType -eq "user"} | export-csv $recommendation_report -NoTypeInformation

write-host ""
write-host "Stale Privileged Member Report can be found here:"
write-host "$recommendation_report" -ForegroundColor Yellow
write-host ""
write-host "Stale Summary by Role:"
import-csv $report | where {$_.LastSignOn -eq "" -and  [int]$($_.RefreshTokenAgeinDays) -gt 120 `
    -and $_.ObjectType -eq "user"} | group role | select name, count | Out-Host
