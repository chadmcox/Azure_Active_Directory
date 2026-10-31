# Azure Active Directory (Microsoft Entra ID) PowerShell

Scripts for reporting on and maintaining Microsoft Entra ID. Check out the [Azure AD Security Wiki](https://github.com/chadmcox/Azure_Active_Directory/wiki) too.

## How the scripts work

- Every script only needs the **Microsoft.Graph.Authentication** module (`Install-Module Microsoft.Graph.Authentication`). They call Microsoft Graph directly with `Invoke-MgGraphRequest` on the **beta** endpoint.
- Every script takes `-Environment Global|USGov|USGovDoD`. Leave it off and the script asks which cloud to use (Enter = Global).
- Reports are written as CSV to your Downloads folder unless you pass `-Path`.
- Scripts that change things support `-WhatIf`, and most have a safety limit such as `-MaxRemovals`.
- Scripts with an `-Identity` switch also run as Azure Automation runbooks with a managed identity. See [Docs/Azure Automation Runbooks.md](Docs/Azure%20Automation%20Runbooks.md).

## Scripts

### Agents

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AgentIdentities.ps1](Agents/Get-AgentIdentities.ps1) | Lists agent identities in Entra ID: agent service principals, agent users and Copilot Studio agent apps, with their last sign-in. | Agent 365\Get Agent Related Service Principals, Agent 365\Get agent related user identities and Applications\get-EntraCopilotServicePrincipals |

### Applications

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AppCredentialChanges.ps1](Applications/Get-AppCredentialChanges.ps1) | Shows who added or changed certificates and secrets on app registrations and service principals, from the audit log. | Logs\whoAddedCredstoSPAPP |
| [Get-AppCredentials.ps1](Applications/Get-AppCredentials.ps1) | Reports every certificate and client secret on app registrations and service principals, with expiry, lifetime and whether it is long-lived. | get-AllAppCredentials and createAADAPPandSPCredentialReport |
| [Get-AppInventory.ps1](Applications/Get-AppInventory.ps1) | Inventories every enabled enterprise app with its sign-in type (SAML, OIDC, password, desktop, app proxy, OAuth2), last sign-in, 30-day sign-in count, owners and whether Entra recommends removing it as unused. | get-EntraApplicationsDetails, get-SPSignInActivity, get-EntraDesktopApplication, get-EntraSAMLApplications, get-StaleAppsfromEntra, get-StaleAppFromRecommendation and Backup\export-ServicePrincipals |
| [Get-AppPermissions.ps1](Applications/Get-AppPermissions.ps1) | Reports every application (app role) and delegated (OAuth2) permission granted to service principals, with optional filters for Exchange, SharePoint, Azure AD Graph and ReadWrite permissions. | the old get-AllAppAssignedPermissions, get-AllAppDelegatedPermissions, get-assignedEXOPerms, get-assignedSPOPerms, get-delegatedEXOPerms, get-delegatedSPOPerms, get-graphAssignedPermissions, get-AppWithEXOFullAccessPerm, get-ADGraphApplications, get-SPToMuchPerms, export-ApplicationConsents, export-ApplicationRoleAssignments and the createAAD*PermissionReport scripts |
| [Get-MicrosoftAppsWithOwners.ps1](Applications/Get-MicrosoftAppsWithOwners.ps1) | Finds Microsoft first-party service principals that have owners assigned. Owners can add credentials to these apps and use their permissions. | get-BuiltinAPPOwners and AzureADModule\get-builtinAppwOwnerAssigned |
| [Remove-ExpiredAppSecrets.ps1](Applications/Remove-ExpiredAppSecrets.ps1) | Removes client secrets that expired more than a set number of days ago from app registrations and service principals. Runs interactively or as an Azure Automation runbook with a managed identity. | Maintenance Task\runbook-removeAADExpiredCredentials |

### Authentication Methods

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-HardwareOathTokens.ps1](Authentication%20Methods/Add-HardwareOathTokens.ps1) | Uploads hardware OATH tokens to Entra ID, one at a time or in bulk from a CSV, and can assign each token to a user. | Hardware Oath Token\upload-HardwareOathToken |
| [Enable-HardwareOathToken.ps1](Authentication%20Methods/Enable-HardwareOathToken.ps1) | Activates a hardware OATH token that is assigned to a user, using a code shown on the token. | Hardware Oath Token\activate-UserHardwareOathToken |
| [Get-MfaRegistration.ps1](Authentication%20Methods/Get-MfaRegistration.ps1) | Reports MFA, SSPR and passwordless registration for members or guests, and flags users who have phone numbers or alternate emails on their account but no registered methods (prepopulated). | create-AADUserMFAReport, create-AADGuestMFAReport, create-AADWH4BRegisteredUsers, get-HybridUserMFAandSSPRState and get-UserSMSPrepopulated |
| [Get-PhoneSignInUsers.ps1](Authentication%20Methods/Get-PhoneSignInUsers.ps1) | Lists users who have a phone number set as a sign-in identity (identities issuer "phone"). | MFA\Get-PhoneIssuer |
| [Get-UserAuthMethods.ps1](Authentication%20Methods/Get-UserAuthMethods.ps1) | Lists every registered authentication method per user with its details: phone numbers and SMS sign-in state, Microsoft Authenticator app version and device, and when each method was last used. | get-phonemethods, get-SMSSignin, get-authenticatorversion and get-UserAuthMethodLastUsedDate |
| [Remove-HardwareOathToken.ps1](Authentication%20Methods/Remove-HardwareOathToken.ps1) | Removes a hardware OATH token from a user so it can be reassigned or retired. | Hardware Oath Token\delete-HardwareOathTokenFromUser (which called the wrong URL) |

### Conditional Access Policy

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-BreakGlassExclusions.ps1](Conditional%20Access%20Policy/Add-BreakGlassExclusions.ps1) | Makes sure the emergency access (break glass) accounts are excluded from every Conditional Access policy and adds them where they are missing. Runs interactively or as an Azure Automation runbook with a managed identity. | add-BreakGlasstoConditionalAccessPolicyExclusion and Maintenance Task\runbook-addAADBreakGlasstoConditionalAccessPolicy |
| [Add-ExclusionGroups.ps1](Conditional%20Access%20Policy/Add-ExclusionGroups.ps1) | Creates one exclusion group per Conditional Access policy inside a restricted administrative unit and adds each group to its policy's exclusions, so exclusions are managed through groups instead of the policies. | add-ExclusionGroupALLCAP |
| [Compare-CABaseline.ps1](Conditional%20Access%20Policy/Compare-CABaseline.ps1) | Compares the tenant's Conditional Access policies against Microsoft's common policy templates and CIS benchmark policies, and lists which existing policies (if any) satisfy each one. | compare-baselineconditionalaccesspoliciestoexistingpolicies and its duplicate Backup\export-ConditionalAccessPolicyMapping |
| [Export-CAPoliciesToCsv.ps1](Conditional%20Access%20Policy/Export-CAPoliciesToCsv.ps1) | Flattens every Conditional Access policy into one CSV row with a column for every setting, by walking each policy object, so new policy settings show up without code changes. | exportConditionalAccessPolicytoCSV |
| [Get-CAExclusions.ps1](Conditional%20Access%20Policy/Get-CAExclusions.ps1) | Lists everyone excluded from each Conditional Access policy, expanding excluded groups (including nested groups) and roles down to the actual users, so exclusions can be reviewed. | exportConditionalAccessExclusions and createConditionalAccessPolicyexclusionstats |
| [Get-CAPolicyReport.ps1](Conditional%20Access%20Policy/Get-CAPolicyReport.ps1) | Reports each Conditional Access policy with how many users it targets and excludes (through users, groups, roles and guests), its apps, conditions, grant and session controls. | count-usersperconditionalaccesspolicy and Backup\export-ConditionalAccessPolicy |
| [Import-RecommendedCAPolicies.ps1](Conditional%20Access%20Policy/Import-RecommendedCAPolicies.ps1) | Imports recommended Conditional Access policies from this repo's JSON file into the tenant in report-only mode, one at a time from a menu or all at once. | Import-AADRecommendedConditionalAccessPolicies |
| [New-TorNamedLocations.ps1](Conditional%20Access%20Policy/New-TorNamedLocations.ps1) | Creates untrusted IP named locations from a public list of Tor exit nodes (1,000 addresses per location), for use in a Conditional Access block policy. | exampletocreatebadiplocations |

### Devices

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-DeviceReport.ps1](Devices/Get-DeviceReport.ps1) | Reports every device in Entra ID with its join type, OS, compliance, last sign-in and owner, and flags stale devices. | Devices\AzureADModule\AzureADDeviceScriptCollection and getAADDevicesStatus |
| [Get-DisabledDevicesInUse.ps1](Devices/Get-DisabledDevicesInUse.ps1) | Finds disabled devices that people are still trying to use, from sign-ins that failed with error 135011 (device disabled), so they can be re-enabled or the users helped before devices are deleted. | Devices\AzureADModule\GetDisabledAADDevicesStillInUse |

### Domains

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-DomainUsage.ps1](Domains/Get-DomainUsage.ps1) | Lists the registered domains and every place each domain is used on users, deleted users, groups, contacts, app registrations and service principals, which is needed before a domain can be removed. | Custom Domain\inventory-everyobjectdomainattribute and Backup\export-RegisteredDomains |

### Groups

| Script | What it does | Replaces |
| --- | --- | --- |
| [Backup-CloudGroups.ps1](Groups/Backup-CloudGroups.ps1) | Backs up cloud-only security groups to JSON: assigned members, dynamic membership rules, owners and app role assignments, so a deleted or changed group can be rebuilt. | backup-CloudSecurityGroupMembers, backup-DynamicSecurityGroupMemberShipRules and backup-GroupsAppRoleAssignment |
| [Export-GroupMemberships.ps1](Groups/Export-GroupMemberships.ps1) | Exports the security groups every member user, guest and group belongs to, including nested membership, as three CSV files. | export-groupsecuritymembership and Backup\export-GroupMemberShips |
| [Get-GroupAppRoleAssignments.ps1](Groups/Get-GroupAppRoleAssignments.ps1) | Lists the apps and app roles every group is assigned to, to find broad groups (like All Users) that grant access to apps. | AzureADModule\getAADAllUsersGroupAppRoleAssignment |
| [Get-GroupReport.ps1](Groups/Get-GroupReport.ps1) | Reports every group with its type, member and owner counts, licenses, dynamic rule state and duplicate names, so empty, ownerless, duplicate and broken dynamic groups can be found in one file. | get-GroupMemberCount, get-EmptySecurityGroups, get-SyncedEmptySecurityGroups, get-OwnerlessSecurityGroups, get-OwnerlessUnifiedGroups, get-DynamicGroupProcessingStateNotOn, get-memberofdynamicgroups, find-DuplicateGroups, Backup\export-Groups and the AzureADModule scripts getAADGroupsMissingOwner, getMemberlessAADGroups, getMemberlessAADUnifiedGroups, getAADLicensedGroups and getAADUnifiedGroupsMissingLifecyclePolicies |

### Guest

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-GuestSponsors.ps1](Guest/Add-GuestSponsors.ps1) | Sets the person who invited each guest as the guest's sponsor, using the "Invite external user" audit events. Runs interactively or as a daily Azure Automation runbook with a managed identity. | add-AADSponsoronGuest and Maintenance Task\runbook-AADAddSponsortoGuest |
| [Get-GuestAccess.ps1](Guest/Get-GuestAccess.ps1) | Exports what guests have access to and own: group memberships, app role assignments and owned objects, for review or as a backup before removing guests. | backup-GuestGroupMembership, backup-GuestAppRoleAssignments and find-GuestOwnedObjects |
| [Get-GuestReport.ps1](Guest/Get-GuestReport.ps1) | Reports every guest with invite state, last sign-in, sponsors and sign-in issuer, and can check whether each guest's home tenant is viral (unmanaged). | create-GuestReport, create-GuestReportV2, create-GuestIsViralReport, create-GuestIsViralReportV2, get-GuestSponsors, get-MGEntraStaleGuest and Backup\export-Guests |
| [Remove-StaleGuests.ps1](Guest/Remove-StaleGuests.ps1) | Deletes guests that have not signed in for a set number of days, or that never accepted their invitation. Runs interactively or as an Azure Automation runbook with a managed identity. Deleted guests stay in the recycle bin for 30 days. | remove-StaleGuest, remove-StalePendingGuest, and Maintenance Task\runbook-removeAADStaleGuest and runbook-removeAADUnacceptedGuest |

### Hybrid Identity

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-SyncAccountSignIns.ps1](Hybrid%20Identity/Get-SyncAccountSignIns.ps1) | Lists the IP addresses and apps used by Directory Synchronization Accounts (Entra Connect sync accounts), to confirm they only sign in from the sync servers. | Azure AD Connect\GetSyncAccountIPs and getSyncAccountSigninApps |

### Identity Protection

| Script | What it does | Replaces |
| --- | --- | --- |
| [Dismiss-RiskyUsers.ps1](Identity%20Protection/Dismiss-RiskyUsers.ps1) | Dismisses user risk that is older than a set number of days for the chosen risk levels. Runs interactively or as an Azure Automation runbook with a managed identity. | dismiss-IdentityProtectionRiskyUsers and Maintenance Task\runbook-dismissAIPRiskyUsers |
| [Get-RiskyUsers.ps1](Identity%20Protection/Get-RiskyUsers.ps1) | Reports users Identity Protection currently marks as at risk, with risk level, when the risk was last updated and whether the user changed their password since. | export-IdentityProtectionAllRiskyUsers and Backup\export-RiskyUsers |

### Intune

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-IntuneRoleAssignments.ps1](Intune/Get-IntuneRoleAssignments.ps1) | Lists every Intune role assignment with the groups and users that hold it and the permissions the role grants. | Intune\get-IntuneRoles (which showed results in Out-GridView) |

### Logs

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AppSignInSummary.ps1](Logs/Get-AppSignInSummary.ps1) | Shows the number of successful and failed sign-ins for each application over the last 7 or 30 days. | exportAADSummaryforApplicationSignins |
| [Get-CriticalAuditEvents.ps1](Logs/Get-CriticalAuditEvents.ps1) | Pulls high-impact audit events, like federation and sync changes, permanent role assignments, new credentials on apps and Conditional Access changes, into one CSV. | Security\gatherAzureADAuditLogs |
| [Get-ExternalTenantSignIns.ps1](Logs/Get-ExternalTenantSignIns.ps1) | Lists the other tenants your users sign in to (as guests or through cross-tenant access), with the tenant name and the apps used. | Users\retrieve-ExternalTenantsUsedByUsers |
| [Get-LegacyAuthSignIns.ps1](Logs/Get-LegacyAuthSignIns.ps1) | Finds sign-ins that used legacy (basic) authentication clients such as IMAP, POP, ActiveSync and older Office clients, grouped by user, app and client. | findBasicAuthExchangeOnline, findBasicAuthSharepointOnline and findBasicAuthSkypeforBusinessOnline |
| [Get-LegacyTlsSignIns.ps1](Logs/Get-LegacyTlsSignIns.ps1) | Finds sign-ins that used legacy TLS (TLS 1.0, 1.1 or 3DES), so the clients can be updated before they stop working. | getlegacytls |
| [Get-UserSignIns.ps1](Logs/Get-UserSignIns.ps1) | Pulls sign-in logs for one user or for a specific error code, including the Conditional Access policies that applied, for troubleshooting and lockout investigations. | viewAADUserSignins, viewAADUserSigninwithCAP and findAccountsWithLockoutEvents (use -ErrorCode 50053) |

### Roles and PIM

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-GroupsToRoles.ps1](Roles%20and%20PIM/Add-GroupsToRoles.ps1) | Creates role-assignable security groups from a CSV of roleName and groupName pairs and gives each group a permanent active assignment to its directory role, so PIM for Groups can control who is in the role. | PIM\addGrouptoRoleinPIM |
| [Export-PimSettings.ps1](Roles%20and%20PIM/Export-PimSettings.ps1) | Exports the PIM settings (role management policy rules) for every directory role and every group onboarded to PIM for Groups, one JSON file per role or group plus a summary CSV. | PIM\export-PIMSettings and the empty PIM\backup-PIMDirectoryRoleSettings |
| [Get-PrivilegeEscalationPaths.ps1](Roles%20and%20PIM/Get-PrivilegeEscalationPaths.ps1) | Finds the users, groups and apps that can change credentials, change group membership or elevate privileges, through Microsoft Graph app permissions, directory roles or ownership of those apps. | Security\Get-AADObjectsCanChangeCred, Get-AADObjectsCanChangeGroupMembership, Get-AADObjectsCanElevatePriv, Roles\AzureADModule\roleAbleTo*, and Applications\get-AppsandOwnersCanChangeAllGroupMembership / get-AppsandOwnersCanAssignAppRoles |
| [Get-RoleAuditEvents.ps1](Roles%20and%20PIM/Get-RoleAuditEvents.ps1) | Pulls audit events about directory roles and their members: role membership and PIM changes, changes made to admin accounts, and changes made by admin accounts. | Roles\auditRoleMembershipChanges, PIM\auditPIMRoleChanges, getAADChangesToGlobalAdmins, getAADChangesbyGlobalAdmins and Security\GatherRoleMemberChanges |
| [Get-RoleMemberAppliedPolicies.ps1](Roles%20and%20PIM/Get-RoleMemberAppliedPolicies.ps1) | Shows which Conditional Access policies were applied to the sign-ins of privileged role members, to spot admins who are not covered. | Roles\getAADRoleCAPused |
| [Get-RoleMembers.ps1](Roles%20and%20PIM/Get-RoleMembers.ps1) | Reports every active and eligible Entra directory role member, expanding role-assignable groups and PIM for Groups, with account state, last sign-in and MFA registration. | ExportAADDirectoryRoleMembers, getAzureADPrivRoleMembers, collectAzureADRoleMembersMFAStatus, getAADInactiveRoleMembers, createAADDirectoryRoleMemberReport, Export-AADRoleMembers, export-PIMROLEMembersstate, export-HighlyPrivAccountsMFA, exportAADPIMRoleMembers, RetrieveAdminsforKQL, Backup\export-DirectoryRoleMembership and Backup\export-PIMDirectoryRoles |

### Security

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-SecureScore.ps1](Security/Get-SecureScore.ps1) | Exports Microsoft Secure Score recommendations with rank, score impact, points achieved, status, category and product, in the same layout as the Defender portal export. | Microsoft Secure Score\get-MicrosoftSecureScorefromGraph |
| [Get-SecurityAlerts.ps1](Security/Get-SecurityAlerts.ps1) | Exports Microsoft Defender XDR and Entra ID Protection security alerts from the last set number of days. | Security Alerts\gather-graphSecurityAlerts, which used the retired legacy alerts API |

### Tenant

| Script | What it does | Replaces |
| --- | --- | --- |
| [Export-TenantSettings.ps1](Tenant/Export-TenantSettings.ps1) | Backs up the main tenant-wide settings to JSON (organization, authorization policy, sync features, authentication methods, admin consent, staged rollout, cross-tenant defaults, security defaults) and licenses to CSV. | getAADSettings (MSOnline) and Backup\export-Settings |
| [Get-TenantLookup.ps1](Tenant/Get-TenantLookup.ps1) | Looks up the Entra tenant behind an email address or domain: tenant ID, name, default domain, namespace type, and whether it is a viral (unmanaged) tenant. | Tenant\istenantviral and Tenant\lookup-tenant |

### Users

| Script | What it does | Replaces |
| --- | --- | --- |
| [Disable-StaleUsers.ps1](Users/Disable-StaleUsers.ps1) | Disables cloud-only member accounts that have not signed in and have not changed their password for a set number of days. Runs interactively or as an Azure Automation runbook with a managed identity. | disable-AADMGStaleUsers |
| [Get-UserDirectReports.ps1](Users/Get-UserDirectReports.ps1) | Lists everyone who reports to a manager, directly or through other managers, all the way down the org chart. | get-AADUsersDirectReports |
| [Get-UserReport.ps1](Users/Get-UserReport.ps1) | Reports every member user with sign-in activity, password age and hybrid sync state, and flags stale accounts, old passwords and synced users that stopped syncing. | create-AADMGUserReport, create-AADUserSigninreport, find-AADMGUsersStaleLastSignIn, find-AADMGUserStalePWD, find-usersnotsyncing, Get-EntraHybridUserPasswordChange, getAADUserSignons, Backup\export-Users and GCC\exportGCCAADUsers (pick USGov or USGovDoD for government clouds) |
| [Get-UsersWithPersonalEmail.ps1](Users/Get-UsersWithPersonalEmail.ps1) | Finds member users whose alternate email addresses (otherMails) are personal mailboxes such as Gmail, Outlook.com or Yahoo, which can be used for password reset. | Security\findAADUsersPersonalAltEmail |

## Other folders

- **Log Analytics** - KQL queries for Log Analytics and Sentinel.
- **_Archive** - older scripts that can't run on Microsoft Graph alone (Azure RBAC with the Az module, on-premises AD, local registry checks, the China cloud). Kept for reference, not maintained.
- **Assessment**, **Docs**, **screen** - notes, guides and images.
