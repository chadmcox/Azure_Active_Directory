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
param($resultfile = "$env:userprofile\Documents\AAD_Application_Consents.csv")

if(!(Get-AzureADCurrentSessionInfo)){
    connect-azuread
}

function getallconsents{
    write-host "Enumerating Delegated Consents"
    foreach($aadsp in ($aadsps | where {$_.serviceprincipaltype -eq 'Application'})){
        write-host "Enumerating Delegated Consents for $($aadsp.displayname)"
        $aadsp | Get-AzureADServicePrincipalOAuth2PermissionGrant -all $true -pv oa2pg | foreach{
            $oa2pg.scope -split(" ") | where {$_} | select `
            @{Name="PermissionType";Expression={"Delegated"}}, `
            @{Name="Risk";Expression={$hash_riskyconsents.ContainsKey($_)}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="ConsentType";Expression={$oa2pg.consenttype}}, `
            @{Name="UserPrincipalName";Expression={$hash_allAADUsers[$oa2pg.PrincipalId].userprincipalname}}, `
            @{Name="UserDisplayName";Expression={$hash_allAADUsers[$oa2pg.PrincipalId].displayname}}, `
            @{Name="UserType";Expression={$hash_allAADUsers[$oa2pg.PrincipalId].usertype}}, `
            @{Name="UserInRoleAdmin";Expression={$hash_aaddirrolemembers.ContainsKey($oa2pg.PrincipalId)}}, `
            @{Name="APPlication";Expression={$aadsp.displayname}}, `
            @{Name="APPlicationObjectID";Expression={$aadsp.ObjectID}}, `
            @{Name="APPlicationPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="APPlicationAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="APPlicationAccountEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="APPlicationURL";Expression={$aadsp.ReplyUrls[0]}}
        }
    }
}
function getallperms{
    write-host "Enumerating Application Consents"
    foreach($aadsp in $aadsps){
        write-host "Enumerating Application Consents for $($aadsp.displayname)"
        $aadsp | Get-AzureADServiceAppRoleAssignedTo -all $true -pv appra | foreach{
            $hash_approles[$($_.id)].value | select `
            @{Name="PermissionType";Expression={"Application"}}, `
            @{Name="Risk";Expression={$hash_riskyconsents.ContainsKey($_)}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="ConsentType";Expression={$oa2pg.consenttype}}, `
            @{Name="UserPrincipalName";Expression={}}, `
            @{Name="UserDisplayName";Expression={}}, `
            @{Name="UserType";Expression={}}, `
            @{Name="UserInRoleAdmin";Expression={}}, `
            @{Name="APPlication";Expression={$aadsp.displayname}}, `
            @{Name="APPlicationObjectID";Expression={$aadsp.ObjectID}}, `
            @{Name="APPlicationPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="APPlicationAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="APPlicationAccountEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="APPlicationURL";Expression={$aadsp.ReplyUrls[0]}}
        }
    }
}

write-host "Retrieving Service Principals"
    $aadsps = Get-AzureADServicePrincipal -Filter "serviceprincipaltype eq 'Application'" -all $true

#this is a table of permissions I 
$hash_riskyconsents = @("User.Read.All","Group.Read.All","Group.Write.All","Directory.ReadWrite.All","Directory.Read.All","ReadWrite.ConditionalAccess","PrivilegedAccess.ReadWrite.AzureAD","Files.Read.All","Files.Read","MailboxSettings.ReadWrite","Files.ReadWrite.All","Files.ReadWrite","EAS.AccessAsUser.All","EWS.AccessAsUser.All","Mail.Read","Mail.Read.Shared","Mail.ReadWrite","Directory.AccessAsUser.All","user_impersonation") | group -AsHashTable -AsString

write-host "Building hash table with all api permissions"
$hash_approles = Get-AzureADServicePrincipal -all $true | select -ExpandProperty AppRoles | select * -Unique | group id -AsHashTable -AsString

write-host "Building user hash table for quick PrincipalId lookup"
$hash_allAADUsers = @{}
get-azureaduser -all $true -pv aadu | select objectid, displayname, userprincipalname, UserType | foreach{
    $hash_allAADUsers.Add($aadu.objectid, @{displayname = $aadu.displayname; userprincipalname = $aadu.userprincipalname; UserType = $aadu.UserType})
}

write-host "Building directory role member hash to display if user is Privileged"
$hash_aaddirrolemembers = Get-AzureADDirectoryRole | where {$_.displayname -like "*administrator*"} | Get-AzureADDirectoryRoleMember | select objectid | group objectid -AsHashTable -AsString

getallconsents | export-csv $resultfile -NoTypeInformation
getallperms  | export-csv $resultfile -NoTypeInformation -Append

write-host "Results can be found here: $resultfile"


