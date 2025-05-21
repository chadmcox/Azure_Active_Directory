#Requires -Module azurerm,msonline
<#PSScriptInfo

.VERSION 0.1

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

.TAGS Get-AzureRmContext Set-AzureRmContext Get-AzureRmRoleAssignment get-msoluser

.DESCRIPTION 
 Ensure that multi-factor authentication is enabled for all Azure Subscription privileged users 

#> 
Param()

function getrbacassignmenttype{
    [CmdletBinding()]
    param($scopeComponents,$objectid)
    $Return = @{} 
    $scopeComponents = $scopeComponents.Split('/')
    #Determine RBAC Assignment Type between Resource, Resource Group, and Subscription Level or Classic Assignment
    if ($scopeComponents[6] -ne $null) {
        $Return.Type="Resource Item"
        $Return.Name=$scopeComponents[6]+"\"+$scopeComponents[7]+"\"+$scopeComponents[8]
    }elseif ($scopeComponents[4] -ne $null){
        $Return.Type="Resource Group"
        $Return.Name=$scopeComponents[4]
    }elseif ($objectid -eq "00000000-0000-0000-0000-000000000000"){
        $Return.Type="Classic Administrator"
        $Return.Name=$scopeComponents[2]
        $Return.roleDefinitionName="Classic Administrator"
    }else{
        $Return.Type="Subscription"
        $Return.Name=$scopeComponents[2]
    } 
    return $return
}
Function getSingleMSOLUserMFAStatus{
    [CmdletBinding()]
    param($upn)
    $userdomain = $upn.split('@')[1]
    $return = @{}

    if($aad_domains | where name -eq $userdomain){
        $msoluser = get-msoluser -UserPrincipalName $upn
        $return.mfaState = $msoluser.StrongAuthenticationRequirements.state
        $return.mfaMethod = $(if($msoluser.StrongAuthenticationMethods){(`
            $AADUser.StrongAuthenticationMethods | where IsDefault -eq $true).MethodType}else{"Not Defined"})
        $return.AuthenticationType = $(($aad_domains | where name -eq $userdomain).authentication)
        $return.MFAStatus = $(whatisMFAResults -account $return)
        return $return
    }
}
Function getAzureRoleAssignments{
    [CmdletBinding()]
    param()
    $fun_results = @()
    write-Information "Enumerating Current User Subscriptions"

    read-host "Press enter, then login with Account  to query Azure Active Directory"
    connect-msolservice
    read-host "Press enter, then login with Account  to query Azure Services"
    Connect-AzureRmAccount


    $AAD_Domains = get-msoldomain
    Set-Variable AAD_Domains -Scope Script
    Get-AzureRmContext -ListAvailable -PipelineVariable AzureRMSub | Set-AzureRmContext | foreach{
        write-Information "Gathering Infromation from $($AzureRMSub.id)"
        Get-AzureRmRoleAssignment -IncludeClassicAdministrators -PipelineVariable AzureRMRA | foreach{
            write-Information "Gathering Information for $($AzureRMRA.DisplayName)"
            $roledefinitionnames = ($AzureRMRA).RoleDefinitionName.split(";")
            foreach($roledefname in $roledefinitionnames){
                $assignment = getrbacassignmenttype -scopeComponents $AzureRMRA.Scope -objectid $AzureRMRA.ObjectId
                $usermfa = getSingleMSOLUserMFAStatus -upn $AzureRMRA.SignInName
                $subinfo = $AzureRMSub.name.split("-")
                $AzureRMRA | select `
                @{Name="SubscriptionID";Expression={$AzureRMSub.Subscription}},`
                @{Name="SubscriptionName";Expression={$subinfo[0]}},`
                @{Name="AssignmentType";Expression={$assignment.type}},`
                @{Name="TargetResource";Expression={$assignment.name}},`
                @{Name="RoleDefinitionName";Expression={$roledefname}},`
                ObjectType,DisplayName,SignInName, `
                @{Name="mfaState";Expression={$usermfa.mfaState}},`
                @{Name="mfaMethod";Expression={$usermfa.mfaMethod}},`
                @{Name="AuthenticationType";Expression={$usermfa.AuthenticationType}},`
                @{Name="MFAStatus";Expression={$usermfa.MFAStatus}}
            }
        }
    }
}

getAzureRoleAssignments
