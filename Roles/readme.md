# List Azure AD Directory Roles
```
PS C:\WINDOWS\system32> Get-MgDirectoryRole | select *


DeletedDateTime      : 
Description          : Can create and manage trust framework policies in the Identity Experience Framework (IEF).
DisplayName          : B2C IEF Policy Administrator
Id                   : 078d4be6-f59a-4764-b8a4-e80c25e0c1fb
Members              : 
RoleTemplateId       : 3edaf663-341e-4475-9f94-5c398ef6c070
ScopedMembers        : 
AdditionalProperties : {}

DeletedDateTime      : 
Description          : Full access to manage devices in Azure AD.
DisplayName          : Cloud Device Administrator
Id                   : 0b26f266-0350-45c1-8eeb-7cf150960cf2
Members              : 
RoleTemplateId       : 7698a772-787b-4ac8-901f-60d6b08affd2
ScopedMembers        : 
AdditionalProperties : {}
```
# Get Azure AD Directory Role by roletemplateid
```
PS C:\WINDOWS\system32> Get-MgDirectoryRole -filter "RoleTemplateId eq '62e90394-69f5-4237-9190-012177145e10'" | select *


DeletedDateTime      : 
Description          : Can manage all aspects of Azure AD and Microsoft services that use Azure AD identities.
DisplayName          : Global Administrator
Id                   : 872e431d-06f1-4cf3-a995-e7aeb164e7c9
Members              : 
RoleTemplateId       : 62e90394-69f5-4237-9190-012177145e10
ScopedMembers        : 
AdditionalProperties : {}
```
# Get Azure AD Directory Role by displayname
```
PS C:\WINDOWS\system32> Get-MgDirectoryRole -filter "displayName eq 'Global Administrator'" | select *


DeletedDateTime      : 
Description          : Can manage all aspects of Azure AD and Microsoft services that use Azure AD identities.
DisplayName          : Global Administrator
Id                   : 872e431d-06f1-4cf3-a995-e7aeb164e7c9
Members              : 
RoleTemplateId       : 62e90394-69f5-4237-9190-012177145e10
ScopedMembers        : 
AdditionalProperties : {}
```
# Get Global Administrator Members by RoleTemplateId
* This is tricky as the items are stored in the additional properties.  because the formatting is wrong have to run it through a foreach in order for it to format to an object.
```
PS C:\WINDOWS\system32> $gaID = Get-MgDirectoryRole -filter "RoleTemplateId eq '62e90394-69f5-4237-9190-012177145e10'"
Get-MgDirectoryRoleMember -DirectoryRoleId $gaID.id | select -ExpandProperty AdditionalProperties | foreach{
    $_ | Convertto-Json -Compress | ConvertFrom-Json
}


@odata.type       : #microsoft.graph.user
businessPhones    : {608-826-3557}
displayName       : MOD Administrator
givenName         : MOD
mail              : admin@M365x437870.OnMicrosoft.com
mobilePhone       : 608-826-3557
preferredLanguage : en-US
surname           : Administrator
userPrincipalName : admin@M365x437870.onmicrosoft.com

@odata.type       : #microsoft.graph.user
businessPhones    : {+1 262 555 0106}
```
