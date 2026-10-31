
## Add a Management Group, Subscription, Resource Group to be managed by PIM

```
PS C:\Temp> $externalid = "/subscriptions/3e49b46f-ac28-4654-8694-6ee0dc924fd1"
Add-AzureADMSPrivilegedResource -ProviderId AzureResources -ExternalId $externalid

```

##R etrieve the PIM resource ID
Using the outvariable, going to store the object in the resourceid variable

```
PS C:\TEMP> Get-AzureADMSPrivilegedResource -ProviderId AzureResources -filter "externalId eq '$externalid'" -OutVariable resourceid


Id                  : 78f5d166-4730-4ae7-affe-1c9abb817a98
ExternalId          : /subscriptions/3e49b46f-ac28-4654-8694-6ee0dc924fd1
Type                : subscription
DisplayName         : Visual Studio Ultimate with MSDN
Status              : Active
RegisteredDateTime  : 10/9/2020 6:17:33 PM
RegisteredRoot      : 
RoleAssignmentCount : 
RoleDefinitionCount : 
Permissions         : 
```

## Retrieve the role.
For this example going to work with the contributor role, will use the where clause to only retrieve that object and will store in a variable called contributor.
```
PS C:\Temp> Get-AzureADMSPrivilegedRoleDefinition -ProviderId AzureResources -ResourceId $resourceid.id | where displayname -eq "Contributor" -OutVariable Contributor


Id                      : b0d08d34-03d8-4e23-866b-cb6c88696dbd
ResourceId              : 78f5d166-4730-4ae7-affe-1c9abb817a98
ExternalId              : /subscriptions/3e49b46f-ac28-4654-8694-6ee0dc924fd1/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c
DisplayName             : Contributor
SubjectCount            : 
EligibleAssignmentCount : 
ActiveAssignmentCount   : 
```

# To view the current members of the contributor role and their status

```
PS C:\Temp> Get-AzureADMSPrivilegedRoleAssignment -ProviderId AzureResources -ResourceId $resourceid.id -filter "RoledefinitionId eq '$($Contributor.id)'"


Id                             : 39a43e7e-7c29-43fe-9be7-7a2d593c8cf9
ResourceId                     : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId               : b0d08d34-03d8-4e23-866b-cb6c88696dbd
SubjectId                      : b0876644-0a73-4105-bab2-8a346aaca72d
LinkedEligibleRoleAssignmentId : 
ExternalId                     : /subscriptions/3e49b46f-ac28-4654-8694-6ee0dc924fd1/providers/Microsoft.Authorization/roleAssignments/39a43e7e-7c29-43fe-9be7-7a2d593c8cf9
StartDateTime                  : 
EndDateTime                    : 
AssignmentState                : Active
MemberType                     : Direct
```
The subjectid is the objectid for the user
```
PS C:\Temp> Get-AzureADObjectByObjectId -ObjectIds b0876644-0a73-4105-bab2-8a346aaca72d

ObjectId                             DisplayName  UserPrincipalName                        UserType
--------                             -----------  -----------------                        --------
b0876644-0a73-4105-bab2-8a346aaca72d Alison Kirby Alison.Kirby@M365x437870.onmicrosoft.com Member  
```

# Change Active Assignment to Eligible
Have to create a schedule object to include with the request.  This can be used to control things like how long someone is alloweds to have access to a role for.  The schedule I have here is just a generic schedule.
```
PS C:\Temp> $schedule = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedSchedule

PS C:\Temp> $schedule.Type = "Once"

PS C:\Temp> Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId AzureResources -ResourceId $resourceid.id `
            -RoleDefinitionId $Contributor.id -SubjectId "b0876644-0a73-4105-bab2-8a346aaca72d" `
            -Type "AdminUpdate" -assignmentState "Eligible" -Schedule $schedule


ResourceId       : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId : b0d08d34-03d8-4e23-866b-cb6c88696dbd
SubjectId        : b0876644-0a73-4105-bab2-8a346aaca72d
Type             : AdminUpdate
AssignmentState  : Eligible
Schedule         : class AzureADMSPrivilegedSchedule {
                     StartDateTime: 10/12/2020 3:58:14 PM
                     EndDateTime: 
                     Type: Once
                     Duration: PT0S
                   }
                   
Reason           : 
```
## Add a new elgible assignment
```
PS C:\Temp> Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId AzureResources -ResourceId $resourceid.id `
            -RoleDefinitionId $Contributor.id -SubjectId "d2ea07f0-fce5-42cc-a12f-5e9d45d22570" `
            -Type "AdminAdd" -assignmentState "Eligible" -Schedule $schedule


ResourceId       : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId : b0d08d34-03d8-4e23-866b-cb6c88696dbd
SubjectId        : d2ea07f0-fce5-42cc-a12f-5e9d45d22570
Type             : AdminAdd
AssignmentState  : Eligible
Schedule         : class AzureADMSPrivilegedSchedule {
                     StartDateTime: 10/12/2020 4:01:48 PM
                     EndDateTime: 
                     Type: Once
                     Duration: PT0S
                   }
                   
Reason           : 
```
## Remove an assignment
```
PS C:\Temp> Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId AzureResources -ResourceId $resourceid.id `
            -RoleDefinitionId $Contributor.id -SubjectId "d2ea07f0-fce5-42cc-a12f-5e9d45d22570" `
            -Type "AdminRemove" -assignmentState "Eligible" -Schedule $schedule


ResourceId       : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId : b0d08d34-03d8-4e23-866b-cb6c88696dbd
SubjectId        : d2ea07f0-fce5-42cc-a12f-5e9d45d22570
Type             : AdminRemove
AssignmentState  : Eligible
Schedule         : class AzureADMSPrivilegedSchedule {
                     StartDateTime: 1/1/0001 12:00:00 AM
                     EndDateTime: 
                     Type: Once
                     Duration: PT0S
                   }
                   
Reason           : 
```
## View the PIM Settings for the role
```
PS C:\Temp> Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "resourceid eq '$($resourceid.id)' and RoleDefinitionId eq '$($Contributor.id)'"


Id                    : 54b8c1e1-53de-4809-94f8-ae11156c740a
ResourceId            : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId      : b0d08d34-03d8-4e23-866b-cb6c88696dbd
IsDefault             : False
LastUpdatedDateTime   : 10/9/2020 7:11:12 PM
LastUpdatedBy         : Chad Cox
AdminEligibleSettings : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"permanentAssignment":true,"maximumGrantPeriodInMinutes":525600}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        }
AdminMemberSettings   : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"permanentAssignment":true,"maximumGrantPeriodInMinutes":259200}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":true}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: JustificationRule
                          Setting: {"required":false}
                        }
                        }
UserEligibleSettings  : {}
UserMemberSettings    : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: TicketingRule
                          Setting: {"ticketingRequired":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: AcrsRule
                          Setting: {"acrsRequired":false,"acrs":null}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"permanentAssignment":true,"maximumGrantPeriodInMinutes":480}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":true}
                        }
                        ...}
```
## Change the settings for the PIM role
### Copy settings from existing role
In most cases I usually set up one role to be the template and then copy it to the others.  for this example the owner role has been set up the way I want the rest of the roles to look. Retrieve the owner role information
```
PS C:\Temp> Get-AzureADMSPrivilegedRoleDefinition -ProviderId AzureResources -ResourceId $resourceid.id | where displayname -eq "Owner" -OutVariable Owner


Id                      : d047c8f6-0921-46f6-b73b-70a6cb50381d
ResourceId              : 78f5d166-4730-4ae7-affe-1c9abb817a98
ExternalId              : /subscriptions/0292f9d1-2712-4325-98ba-fbc2b5058169/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635
DisplayName             : Owner
SubjectCount            : 
EligibleAssignmentCount : 
ActiveAssignmentCount   : 

PS C:\Temp> Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "resourceid eq '$($resourceid.id)' and RoleDefinitionId eq '$($Owner.id)'" -OutVariable ownersettings


Id                    : d2e12ba8-2edc-4eb3-8a90-45a27a33cf48
ResourceId            : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId      : d047c8f6-0921-46f6-b73b-70a6cb50381d
IsDefault             : True
LastUpdatedDateTime   : 
LastUpdatedBy         : 
AdminEligibleSettings : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"365.00:00:00","maximumGrantPeriodInMinutes":525600,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        }
AdminMemberSettings   : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"180.00:00:00","maximumGrantPeriodInMinutes":259200,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: JustificationRule
                          Setting: {"required":true}
                        }
                        }
UserEligibleSettings  : {}
UserMemberSettings    : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"08:00:00","maximumGrantPeriodInMinutes":480,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: JustificationRule
                          Setting: {"required":true}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ApprovalRule
                          Setting: {"enabled":false,"isCriteriaSupported":false,"approvers":null,"businessFlowId":null,"hasNotificationPolicy":false}
                        }
                        ...}
```
Stored the owner's settings objects in a variable called ownersettings, using the outvariable parameter.  will retrieve the contributor settings and store in a variable.

```
PS C:\Temp> Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "resourceid eq '$($resourceid.id)' and RoleDefinitionId eq '$($Contributor.id)'" -outvariable Contributorsettings


Id                    : 54b8c1e1-53de-4809-94f8-ae11156c740a
ResourceId            : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId      : b0d08d34-03d8-4e23-866b-cb6c88696dbd
IsDefault             : False
```
Now change the settings
```
PS C:\Temp> Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $Contributorsettings.id -AdminEligibleSettings $ownersettings.AdminEligibleSettings `
    -AdminMemberSettings $ownersettings.AdminMemberSettings -UserEligibleSettings $ownersettings.UserEligibleSettings `
        -UserMemberSettings $ownersettings.UserMemberSettings
```
Now Validate the settings took place, note in the usermembersettings the requiremfa is now false.
```
PS C:\Temp> Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "resourceid eq '$($resourceid.id)' and RoleDefinitionId eq '$($Contributor.id)'" -outvariable Contributorsettings


Id                    : 54b8c1e1-53de-4809-94f8-ae11156c740a
ResourceId            : 78f5d166-4730-4ae7-affe-1c9abb817a98
RoleDefinitionId      : b0d08d34-03d8-4e23-866b-cb6c88696dbd
IsDefault             : False
LastUpdatedDateTime   : 10/12/2020 4:38:15 PM
LastUpdatedBy         : Chad Cox
AdminEligibleSettings : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"365.00:00:00","maximumGrantPeriodInMinutes":525600,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        }
AdminMemberSettings   : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"180.00:00:00","maximumGrantPeriodInMinutes":259200,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: JustificationRule
                          Setting: {"required":true}
                        }
                        }
UserEligibleSettings  : {}
UserMemberSettings    : {class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ExpirationRule
                          Setting: {"maximumGrantPeriod":"08:00:00","maximumGrantPeriodInMinutes":480,"permanentAssignment":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: MfaRule
                          Setting: {"mfaRequired":false}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: JustificationRule
                          Setting: {"required":true}
                        }
                        , class AzureADMSPrivilegedRuleSetting {
                          RuleIdentifier: ApprovalRule
                          Setting: {}
                        }
                        ...}
```
### To change settings creating Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting objects.
Just going to change one setting in the usermembersettings so that mfarequire is true.
```
PS C:\Temp> $setting = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting

PS C:\Temp> $setting.RuleIdentifier = "MfaRule"

PS C:\Temp> $setting.Setting = "{'required':true}"

PS C:\Temp> Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $Contributorsettings.id -UserMemberSettings $setting

PS C:\Temp> Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "resourceid eq '$($resourceid.id)' and RoleDefinitionId eq '$($Contributor.id)'" | select -ExpandProperty UserMemberSettings

RuleIdentifier    Setting                                                                                        
--------------    -------                                                                                        
MfaRule           {'required':true}                                                                              
TicketingRule     {"ticketingRequired":false}                                                                    
AcrsRule          {"acrsRequired":false,"acrs":null}                                                             
ExpirationRule    {"maximumGrantPeriod":"08:00:00","maximumGrantPeriodInMinutes":480,"permanentAssignment":false}
JustificationRule {"required":true}                                                                              
ApprovalRule      {}    
```

### Notification rules are not prime time yet but going to throw this one here.  This particular setting is only to make sure the PIM admins dont get notified everytime someone elevates a role.
its possible to use this in the admin settings as well but, for what ever reason if you set it against the others it will clear the user member notification settings.  I assume this is what happens when dealing with non published features.  Also because the feature isnt published its not possible to query the settings for notifications as of 10/12/2020
```
PS C:\Temp> $AdminNotificationRule = [Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting]::new("NotificationRule",'{"policies":[{"deliveryMechanism":"email","setting":[{"customreceivers":null,"isdefaultreceiverenabled":false,"notificationlevel":2,"recipienttype":2},{"customreceivers":null,"isdefaultreceiverenabled":true,"notificationlevel":2,"recipienttype":0},{"customreceivers":null,"isdefaultreceiverenabled":true,"notificationlevel":2,"recipienttype":1}]}]}')

PS C:\Temp> Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $Contributorsettings.id -UserMemberSettings $AdminNotificationRule
```
