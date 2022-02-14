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

.EXAMPLE

#>
param($reportpath="$env:userprofile\Documents",$staledays=120)
$report = "$reportpath\$((Get-AzureADTenantDetail).DisplayName)_AAD_UserSignons_$(get-date -f yyyy-MM-dd-HH-mm).csv"

function getaadlastazureadlogon{
param($upn)
    <#this functions checks to see if the objected has signed in over the last 30 days#>
    $last_signon_date = (Get-AzureADAuditSignInLogs -Filter "userPrincipalName eq '$upn'" -top 1).CreatedDateTime
    if($last_signon_date){get-date $last_signon_date -Format MM/dd/yyyy}
}
function getmailboxtype{
    param($rtd)
    #create hash table to decipher code
    $MSExchRecipientTypeDetails = @{
            1="UserMailbox"
            2="LinkedMailbox"
            4="SharedMailbox"
            8="LegacyMailbox"
            16="RoomMailbox"
            32="EquipmentMailbox"
            64="MailContact"
            128="MailUser"
            256="MailUniversalDistributionGroup"
            512="MailNonUniversalGroup"
            1024="MailUniversalSecurityGroup"
            2048="DynamicDistributionGroup"
            4096="Public Folder"
            8192="SystemAttendantMailbox"
            16384="SystemMailbox"
            32768="MailForestContact"
            65536="User"
            131072="Contact"
            262144="UniversalDistributionGroup"
            524288="UniversalSecurityGroup"
            1048576="NonUniversalGroup"
            2097152="DisabledUser"
            4194304="MicrosoftExchange"
            8388608="ArbitrationMailbox"
            16777216="MailboxPlan"
            33554432="LinkedUser"
            268435456="RoomList"
            536870912="DiscoveryMailbox"
            1073741824="RoleGroup"
            2147483648="RemoteMailbox"
            137438953472="TeamMailbox"
            8589934592="RemoteRoomMailbox"
            17179869184="RemoteEquipmentMailbox"
            34359738368="RemoteSharedMailbox" }
            $MSExchRecipientTypeDetails[$rtd]
}

write-host "Retrieving users from AzureAD"
#$users = get-MsolUser -all -PipelineVariable AADUser | where {$aaduser.usertype -eq "Member"}

write-host "Populating results"
@(foreach($user in $users){
    $user | select objectid, UserPrincipalName,BlockCredential,MSExchRecipientTypeDetails, `
    @{N="MailboxType";E={getmailboxtype -rtd ($user).MSExchRecipientTypeDetails}}, `
    @{N="StsRefreshTokensValidFrom";E={get-date $($_.StsRefreshTokensValidFrom) -f MM/dd/yyyy}}, `
    @{N="LastPasswordChangeTimestamp";E={if($_.LastPasswordChangeTimestamp){
      get-date $($_.LastPasswordChangeTimestamp) -f MM/dd/yyyy}else{$null}}}, `
    @{N='LastSignOn';E={getaadlastazureadlogon -upn $_.userprincipalname}}
}) | export-csv $report -NoTypeInformation

write-host "Results can be found here: $report"
