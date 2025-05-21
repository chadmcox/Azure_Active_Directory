#requires -modules azureadpreview
<#PSScriptInfo
.VERSION 2021.1.6
.GUID 7ac2eb59-9660-4225-bea4-4cfaff1c8a4f
.AUTHOR Chad Cox
.COMPANYNAME Microsoft
.description
This report will report on all permissions given to applications in Azure AD.
.notes
the list of risky consents is based on ones found at a particular time.
.references
Detecting Abuse of Authentication Mechanisms
https://media.defense.gov/2020/Dec/17/2002554125/-1/-1/0/AUTHENTICATION_MECHANISMS_CSA_U_OO_198854_20.PDF
Protecting Microsoft 365 from on-premises attacks
https://techcommunity.microsoft.com/t5/azure-active-directory-identity/protecting-microsoft-365-from-on-premises-attacks/ba-p/1751754
Understanding "Solorigate"'s Identity IOCs - for Identity Vendors and their customers.
https://techcommunity.microsoft.com/t5/azure-active-directory-identity/understanding-quot-solorigate-quot-s-identity-iocs-for-identity/ba-p/2007610
Detect and Remediate Illicit Consent Grants
https://docs.microsoft.com/en-us/microsoft-365/security/office-365-security/detect-and-remediate-illicit-consent-grants?view=o365-worldwide
#>
param($resultfile = "$env:userprofile\Documents\AAD_Directory_Role_Members.csv")

if(!(Get-AzureADCurrentSessionInfo)){
    connect-azuread
}

function retrieveAADRoleMembers{

    Get-AzureADDirectoryRole -pv aadr | Get-AzureADDirectoryRoleMember | select `
        @{Name="Query";Expression={"Directory Role"}}, `
        @{Name="RoleID";Expression={$aadr.objectid}}, `
        @{Name="RoleName";Expression={if($aadr.displayName -eq "Company Administrator"){"Global Administrator"}else{$aadr.displayName}}}, `
        @{Name="RoleType";Expression={$aadr.objecttype}}, `
        ObjectID, Displayname, UserPrincipalName, AccountEnabled, DirSyncEnabled,ObjectType,UserType, `
        @{Name="UsedLast30Days";Expression={if($_.objecttype -eq "user"){if(Get-AzureADAuditSignInLogs -Filter "userid eq '$($_.objectid)'" -top 1){$true}else{$false}}}}, `
        RefreshTokensValidFromDateTime, `
        @{Name="ValidSPCredential";Expression={if($_.objecttype -eq "serviceprincipal"){if($_ | `
            where {$_.PasswordCredentials.enddate -lt (get-date).DateTime -or $_.KeyCredentials.enddate -lt (get-date).DateTime}){$true}}}}

    Get-AzureADMSPrivilegedRoleDefinition -ProviderId "aadRoles" -ResourceId $((Get-AzureADTenantDetail).objectid) -PipelineVariable aadr |  foreach{
        Get-AzureADMSPrivilegedRoleAssignment -ProviderId "aadRoles" -ResourceId $((Get-AzureADTenantDetail).objectid) `
            -filter "RoleDefinitionId eq '$($aadr.id)'" -PipelineVariable ra | foreach{
                Get-AzureADObjectByObjectId -ObjectIds $ra.subjectid -PipelineVariable rolemem | select `
                    @{Name="Query";Expression={"PIM"}}, `
                    @{Name="RoleID";Expression={$aadr.ExternalId}}, `
                    @{Name="RoleName";Expression={$aadr.displayName}}, `
                    @{Name="RoleType";Expression={"Role"}}, `
                    @{Name="AssignmentState";Expression={$ra.assignmentstate}}, `
                    @{Name="Permanant";Expression={if($ra.AssignmentState -eq "Active" -and $ra.EndDateTime -eq $null){$true}else{$false}}}, `
                    @{Name="StartDateTime";Expression={$ra.StartDateTime}}, `
                    @{Name="EndDateTime";Expression={$ra.EndDateTime}}, `
                    ObjectID, Displayname, UserPrincipalName, AccountEnabled, DirSyncEnabled, ObjectType, UserType, `
                    @{Name="UsedLast30Days";Expression={if($_.objecttype -eq "user"){if(Get-AzureADAuditSignInLogs -Filter "userid eq '$($_.objectid)'" -top 1){$true}else{$false}}}}, `}}


}

$tenant = Get-AzureADTenantDetail

retrieveAADRoleMembers | select fromPIM,RoleID,RoleName,RoleType,AssignmentState,ObjectID,Displayname,UserPrincipalName,AccountEnabled,DirSyncEnabled, `
   ObjectType,UserType,UsedLast30Days, RefreshTokensValidFromDateTime, ValidSPCredential, Permanant, StartDateTime, EndDateTime | export-csv $resultfile -NoTypeInformation

