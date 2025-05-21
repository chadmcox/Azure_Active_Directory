#Requires -Module msonline
<#PSScriptInfo

.VERSION 0.1

.GUID b0e5d2c5-9a6b-4026-9742-69c2d7aee260

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
 Ensure that multi-factor authentication is enabled for all Azure AD privileged users

#> 
Param()

function gatherAzureADRoleMembersUsingMSOL{
    [CmdletBinding()]
    param()
    read-host "Press enter, then login with Account to query Azure Active Directory"
    #connect-msolservice

    #this will be used to determine if account is federated or not.

    $AAD_Domains = get-msoldomain
    Set-Variable AAD_Domains -Scope Script

    #query every role in use within Azure AD
    Get-msolRole -PipelineVariable role| foreach {
        #query each one of the roles members
        Get-MsolRoleMember -RoleObjectId $role.objectid -pipelinevariable RoleMem | select objectid,RoleMemberType | `
            where RoleMemberType -eq "User" | foreach{
                #call function to get individual users in realtime.
                getSingleMSOLUserMFAStatus -objectid $RoleMem.objectid | select `
                    @{Name="Role";Expression={$role.name}},`
                    UserPrincipalName,DisplayName,UserType,StsRefreshTokensValidFrom, `
                    BlockCredential,LastDirSyncTime,ObjectId,mfaState,mfaDateTime,mfaMethod,`
                    AuthenticationType,MFAStatus
        }  
    }
}
Function getSingleMSOLUserMFAStatus{
    [CmdletBinding()]
    param($objectid)
    #this functions sole purpose is to query each user that is returned from the     
    $return = get-msoluser -objectid $objectid

    #get users domain from the upn
    $userdomain = $return.UserPrincipalName.split('@')[1]

    #create a hash table
    $hash = @{}
    $hash.mfaState = $return.StrongAuthenticationRequirements.state
    $hash.AuthenticationType = ($aad_domains | where name -eq $userdomain).authentication

    #create the object
    return $return | select `
        UserPrincipalName,DisplayName,UserType,StsRefreshTokensValidFrom, `
        BlockCredential,LastDirSyncTime,ObjectId,
        @{Name="mfaState";Expression={$hash.mfaState}}, `
        @{Name="mfaMethod";Expression={$(if($_.StrongAuthenticationMethods){(`
            $_.StrongAuthenticationMethods | where IsDefault -eq $true).MethodType}else{"Not Defined"})}}, `
        @{Name="AuthenticationType";Expression={$hash.AuthenticationType}}, `
        @{Name="mfaStatus";Expression={whatisMFAResults -account $hash}}

}
Function whatisMFAResults{
    [CmdletBinding()]
    param($account)
    #should change this two param groups but lazy, or could change code, 
    #this function is used to determine status of the user's mfa
    write-information "Starting whatisMFAResults"
    if(($account.mfaState -eq "Enforced" -or $account.mfaState -eq "Enabled") -and `
        ($account.AuthenticationType -eq "Managed" -or $account.AuthenticationType -eq "Federated"))
    {
        return "Success"
    }elseif($account.AuthenticationType -eq "Federated"){
        return "Review"
    }else{
        return "Failed"
    }
}

gatherAzureADRoleMembersUsingMSOL
