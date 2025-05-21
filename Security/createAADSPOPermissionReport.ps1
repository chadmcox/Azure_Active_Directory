#requires -modules azureadpreview
<#PSScriptInfo
.VERSION 2021.1.6

.GUID 551537f4-e8ed-440a-b583-8b68e6b42767

.AUTHOR Chad Cox

.COMPANYNAME Microsoft

.description


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
$permissions = "Sites.FullControl.All","Sites.Manage.All","Sites.Read.All","Sites.ReadWrite.All","Files.Read.All","Files.ReadWrite.All","File.Read.All"

write-host "Retrieving Service Principals"
$aadsps = Get-AzureADServicePrincipal -Filter "serviceprincipaltype eq 'Application'" -all $true | `
    where {$_.PublisherName -ne "Microsoft" -and $_.PublisherName -ne "Microsoft Services"}

write-host "Building hash table with all api permissions"
$hash_approles = Get-AzureADServicePrincipal -all $true  | select -ExpandProperty AppRoles  | where {$_.value -in $permissions} | group id -AsHashTable -AsString
$hash_approles_desc = Get-AzureADServicePrincipal -all $true | select -ExpandProperty AppRoles | where {$_.value -in $permissions} | group value -AsHashTable -AsString

function getallAADAPPconsents{
    write-host "Enumerating Delegated Consents"
    $i = 1
    foreach($aadsp in ($aadsps | where {$_.serviceprincipaltype -eq 'Application'})){
        $aadsp | Get-AzureADServicePrincipalOAuth2PermissionGrant -top 2 -pv oa2pg | foreach{
            $oa2pg.scope -split(" ") | where {$_ -in $permissions} | select `
            @{Name="PermissionType";Expression={"Delegated"}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="ScopeName";Expression={($hash_approles_desc[$_].displayname)[0]}}, `
            @{Name="Application";Expression={$aadsp.displayname}}, `
            @{Name="ApplicationObjectID";Expression={$aadsp.ObjectID}}, `
            @{Name="ApplicationPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="ApplicationAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="ApplicationAccountEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="ApplicationURL";Expression={$aadsp.ReplyUrls[0]}}, `
            @{Name="ApplicationOwner";Expression={"NA"}}, `
            @{Name="LoggedintoLast30days";Expression={if(Get-AzureADAuditSignInLogs -Filter "appId eq '$($aadsp.appid)'" -Top 1){$true}else{$False}}}

        } 
    }
}
function getallAADAPPperms{
    write-host "Enumerating Application Consents"
    foreach($aadsp in $aadsps){
        $aadsp | Get-AzureADServiceAppRoleAssignedTo -all $true -pv appra | foreach{
            $hash_approles[$($_.id)].value | where {$_ -in $permissions} | select `
            @{Name="PermissionType";Expression={"Application"}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="ScopeName";Expression={($hash_approles_desc[$_].displayname)[0]}}, `
            @{Name="Application";Expression={$aadsp.displayname}}, `
            @{Name="ApplicationObjectID";Expression={$aadsp.ObjectID}}, `
            @{Name="ApplicationPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="ApplicationAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="ApplicationAccountEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="ApplicationURL";Expression={$aadsp.ReplyUrls[0]}}, `
            @{Name="ApplicationOwner";Expression={[string](Get-AzureADServicePrincipalOwner -ObjectId $aadsp.ObjectID).UserPrincipalName}}, `
            @{Name="LoggedintoLast30days";Expression={"NA"}}
        }
    }
}
function returnapps{
    getallAADAPPconsents | select * -unique
    getallAADAPPperms | select * -unique
}

returnapps | export-csv ".\$((Get-AzureADTenantDetail).DisplayName)_AAD_SPO_Permissions.csv" -NoTypeInformation
