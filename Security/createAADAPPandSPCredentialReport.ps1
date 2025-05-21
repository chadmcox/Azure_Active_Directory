#requires -modules azureadpreview
<#PSScriptInfo
.VERSION 2021.1.6
.GUID 7ac2eb59-9660-4225-bea4-4cfaff1c8a4f
.AUTHOR Chad Cox
.COMPANYNAME Microsoft
.description
this will report on every application and service principal credential
.notes

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
param($resultfile = "$env:userprofile\Documents\AAD_APPandSP_Credentials.csv")

if(!(Get-AzureADCurrentSessionInfo)){
    connect-azuread
}
function retrieveAADCredentials{
    write-host "Gathering All AAD Service Principals"
    Get-AzureADServicePrincipal -all $true | where {$_.PasswordCredentials -like "*" -or $_.KeyCredentials -like "*"} | select objectid, displayname, objecttype, PasswordCredentials, KeyCredentials, appid
    write-host "Gathering All AAD Applications"
    Get-AzureADApplication -all $true | where {$_.PasswordCredentials -like "*" -or $_.KeyCredentials -like "*"} | select objectid, displayname, objecttype, PasswordCredentials, KeyCredentials, appid
}

function auditAADcredential{
    #thing = I ran out of variable names
    foreach($thing in retrieveAADCredentials){
        $thing.PasswordCredentials | select `
            @{Name="ObjectId";Expression={$thing.objectid}}, `
            @{Name="DisplayName";Expression={$thing.Displayname}}, `
            @{Name="ObjectType";Expression={$thing.ObjectType}}, `
            @{Name="CredentialType";Expression={"Password"}}, `
            @{Name="StartDate";Expression={$_.StartDate}}, `
            @{Name="EndDate";Expression={$_.EndDate}}, `
            @{Name="Expired";Expression={$_.enddate -lt (get-date).DateTime}}, `
            @{Name="AtRisk";Expression={(New-TimeSpan -start $_.StartDate -end $_.EndDate).days -gt 366}}
        $thing.KeyCredentials | select `
            @{Name="ObjectId";Expression={$thing.objectid}}, `
            @{Name="DisplayName";Expression={$thing.Displayname}}, `
            @{Name="ObjectType";Expression={$thing.ObjectType}}, `
            @{Name="CredentialType";Expression={"Key"}}, `
            @{Name="StartDate";Expression={$_.StartDate}}, `
            @{Name="EndDate";Expression={$_.EndDate}}, `
            @{Name="Expired";Expression={$_.enddate -lt (get-date).DateTime}}, `
            @{Name="AtRisk";Expression={(New-TimeSpan -start $_.StartDate -end $_.EndDate).days -gt 366}}
    }
}

auditAADcredential | export-csv $resultfile -NoTypeInformation
write-host "Finished Results can be found here: $resultfile"

