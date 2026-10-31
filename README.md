# Azure Active Directory (Microsoft Entra ID) PowerShell

Scripts for reporting on and maintaining Microsoft Entra ID (formerly Azure Active Directory). Check out the [Azure AD Security Wiki](https://github.com/chadmcox/Azure_Active_Directory/wiki) too.

## How the scripts work

- Every script only needs the **Microsoft.Graph.Authentication** module (`Install-Module Microsoft.Graph.Authentication`). They call Microsoft Graph directly with `Invoke-MgGraphRequest` on the **beta** endpoint.
- Every script takes `-Environment Global|USGov|USGovDoD`. Leave it off and the script asks which cloud to use (Enter = Global).
- Reports are written as CSV to your Downloads folder unless you pass `-Path`.
- Scripts that change things support `-WhatIf` and have a safety limit such as `-MaxRemovals`. Scripts with an `-Identity` switch can also run in Azure Automation with a managed identity (import Microsoft.Graph.Authentication into the Automation account).
- Need a runbook with **no modules at all**? Use the [Maintenance Task](Maintenance%20Task) folder.
- Rules for adding or changing scripts are in [AGENTS.md](AGENTS.md).

## Stale objects

Each object type has a report and a remediation script. Run the report, review the CSV (delete the rows you want to keep), then pass it to the remediation script with `-CsvPath`. Run it with `-WhatIf` first. Every object is checked again before it's changed, so anything that became active after the report is skipped.

| Object | Stale report | Remediate | What remediation does |
| --- | --- | --- | --- |
| Users | [Get-StaleUsers.ps1](Users/Get-StaleUsers.ps1) | [Disable-StaleUsers.ps1](Users/Disable-StaleUsers.ps1) | Disables cloud-only accounts; synced accounts are flagged for AD. Agent users are left out (see Agent ID) |
| Guests | [Get-StaleGuests.ps1](Guest/Get-StaleGuests.ps1) | [Remove-StaleGuests.ps1](Guest/Remove-StaleGuests.ps1) | Deletes inactive guests and old pending invites (30-day recycle bin) |
| Agent ID | [Get-StaleAgentIdentities.ps1](Agent%20ID/Get-StaleAgentIdentities.ps1) | [Disable-StaleAgentIdentities.ps1](Agent%20ID/Disable-StaleAgentIdentities.ps1) | Disables agent identities (service principals), agent users and idle blueprint principals; blueprints are only reported |
| Enterprise apps | [Get-StaleApps.ps1](Applications/Get-StaleApps.ps1) | [Disable-StaleApps.ps1](Applications/Disable-StaleApps.ps1) | Disables the service principal (reversible); skips Microsoft and agent apps |
| App secrets | [Get-AppCredentials.ps1](Applications/Get-AppCredentials.ps1) | [Remove-ExpiredAppSecrets.ps1](Applications/Remove-ExpiredAppSecrets.ps1) | Removes expired client secrets |
| Devices | [Get-StaleDevices.ps1](Devices/Get-StaleDevices.ps1) | [Remove-StaleDevices.ps1](Devices/Remove-StaleDevices.ps1) | `-Action Disable` first, then `-Action Delete`; skips hybrid joined and Autopilot |
| Groups | [Get-StaleGroups.ps1](Groups/Get-StaleGroups.ps1) | [Remove-StaleGroups.ps1](Groups/Remove-StaleGroups.ps1) | Deletes empty, unused cloud groups after a JSON backup |
| Role assignments | [Get-StaleRoleAssignments.ps1](Roles%20and%20PIM/Get-StaleRoleAssignments.ps1) | [Remove-StaleRoleAssignments.ps1](Roles%20and%20PIM/Remove-StaleRoleAssignments.ps1) | Removes assignments held by disabled or inactive accounts and eligible roles never activated; never Global Administrator |
| Conditional Access | [Get-StaleCAObjects.ps1](Conditional%20Access%20Policy/Get-StaleCAObjects.ps1) | [Remove-StaleCAObjects.ps1](Conditional%20Access%20Policy/Remove-StaleCAObjects.ps1) | Removes references to deleted objects and deletes unused named locations; never deletes a policy |
| Authentication methods | [Get-StaleAuthMethods.ps1](Authentication%20Methods/Get-StaleAuthMethods.ps1) | [Remove-StaleAuthMethods.ps1](Authentication%20Methods/Remove-StaleAuthMethods.ps1) | Removes methods not used in the window; never a user's last method |
| Domains | [Get-StaleDomains.ps1](Domains/Get-StaleDomains.ps1) | [Remove-StaleDomains.ps1](Domains/Remove-StaleDomains.ps1) | Deletes unverified domains (and unused verified ones with `-IncludeVerified`) |
| Licenses | [Get-StaleLicenses.ps1](Licenses/Get-StaleLicenses.ps1) | [Remove-StaleLicenses.ps1](Licenses/Remove-StaleLicenses.ps1) | Removes direct license assignments from disabled and inactive accounts; group licenses are flagged |
| Risky users | [Get-RiskyUsers.ps1](Identity%20Protection/Get-RiskyUsers.ps1) | [Dismiss-RiskyUsers.ps1](Identity%20Protection/Dismiss-RiskyUsers.ps1) | Dismisses old low and medium user risk |

## Microsoft Entra operations guide coverage

Tasks from the [Microsoft Entra operations reference guide](https://learn.microsoft.com/en-us/entra/architecture/ops-guide-intro) and the scripts that check them.

| Guide section | Task | Scripts |
| --- | --- | --- |
| Identity and access | Find and fix sync errors older than 100 days | [Get-SyncErrors.ps1](Hybrid%20Identity/Get-SyncErrors.ps1) |
| Identity and access | Sync running on schedule, password hash sync on, sync features | [Get-HybridHealth.ps1](Hybrid%20Identity/Get-HybridHealth.ps1) |
| Identity and access | Group-based licensing, license errors, assigned versus available | [Get-LicenseReport.ps1](Licenses/Get-LicenseReport.ps1), [Get-StaleLicenses.ps1](Licenses/Get-StaleLicenses.ps1) |
| Identity and access | Apps and Conditional Access using the All Users group | [Get-AppAssignments.ps1](Applications/Get-AppAssignments.ps1), [Get-GroupAppRoleAssignments.ps1](Groups/Get-GroupAppRoleAssignments.ps1), [Get-CAPolicyReport.ps1](Conditional%20Access%20Policy/Get-CAPolicyReport.ps1) |
| Identity and access | Automated user provisioning to apps | [Get-AppProvisioningStatus.ps1](Applications/Get-AppProvisioningStatus.ps1) |
| Authentication | MFA and SSPR registration, Windows Hello for Business | [Get-MfaRegistration.ps1](Authentication%20Methods/Get-MfaRegistration.ps1) |
| Authentication | Password protection, smart lockout, password hash sync | [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1) |
| Authentication | Service principals with password credentials | [Get-AppCredentials.ps1](Applications/Get-AppCredentials.ps1) |
| Authentication | Device trust (hybrid join, compliance) | [Get-DeviceReport.ps1](Devices/Get-DeviceReport.ps1), [Compare-CABaseline.ps1](Conditional%20Access%20Policy/Compare-CABaseline.ps1) |
| Authentication | Single sign-on for apps | [Get-AppInventory.ps1](Applications/Get-AppInventory.ps1) |
| Authentication | Migrate AD FS apps to Entra ID | [Get-AdfsAppMigration.ps1](Hybrid%20Identity/Get-AdfsAppMigration.ps1) |
| Authentication | Assign apps to groups, not individual users | [Get-AppAssignments.ps1](Applications/Get-AppAssignments.ps1) |
| Authentication | Named locations, risk-based policies, legacy auth block | [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1), [Compare-CABaseline.ps1](Conditional%20Access%20Policy/Compare-CABaseline.ps1) |
| Authentication | Conditional Access best practices and exclusion groups | [Get-CAPolicyReport.ps1](Conditional%20Access%20Policy/Get-CAPolicyReport.ps1), [Get-CAExclusions.ps1](Conditional%20Access%20Policy/Get-CAExclusions.ps1), [Add-ExclusionGroups.ps1](Conditional%20Access%20Policy/Add-ExclusionGroups.ps1), [Add-BreakGlassExclusions.ps1](Conditional%20Access%20Policy/Add-BreakGlassExclusions.ps1) |
| Authentication | Replace per-user MFA with Conditional Access | [Get-PerUserMfaState.ps1](Authentication%20Methods/Get-PerUserMfaState.ps1) |
| Authentication | Find and lock down legacy authentication | [Get-LegacyAuthSignIns.ps1](Logs/Get-LegacyAuthSignIns.ps1) |
| Authentication | Detect and remove illicit consent grants | [Get-AppPermissions.ps1](Applications/Get-AppPermissions.ps1) |
| Authentication | Lock down user and group settings (app registration, group creation, guest invites, consent) | [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1) |
| Authentication | Traffic from unexpected locations | [Get-SignInLocations.ps1](Logs/Get-SignInLocations.ps1) |
| Governance | Regularly review access to apps, external identities, privileged roles and CA exceptions | [Get-AccessReviewCoverage.ps1](Identity%20Governance/Get-AccessReviewCoverage.ps1) |
| Governance | Review who has privileged roles; just-in-time access | [Get-RoleMembers.ps1](Roles%20and%20PIM/Get-RoleMembers.ps1), [Get-StaleRoleAssignments.ps1](Roles%20and%20PIM/Get-StaleRoleAssignments.ps1), [Export-PimSettings.ps1](Roles%20and%20PIM/Export-PimSettings.ps1) |
| Governance | Two cloud-only emergency access accounts | [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1) |
| Governance | Regularly review consent grants | [Get-AppPermissions.ps1](Applications/Get-AppPermissions.ps1) |
| Governance | Entitlement management catalogs and access packages | [Get-AccessPackages.ps1](Identity%20Governance/Get-AccessPackages.ps1) |
| Operations | Identity secure score | [Get-SecureScore.ps1](Security/Get-SecureScore.ps1) |
| Operations | On-premises agents up to date and redundant (pass-through auth, private network connectors, provisioning agents) | [Get-HybridHealth.ps1](Hybrid%20Identity/Get-HybridHealth.ps1) |
| Operations | Notification contacts and email-capable Global Administrators | [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1) |

These tasks can't be checked through Microsoft Graph, so there's no script for them:

- Entra Connect server version, staging server, source anchor and sync rules (check on the Connect server or with the Entra Connect Configuration Documenter)
- Entra Connect Health alerts and on-premises agent logs (Entra admin center or your SIEM)
- Archiving sign-in and audit logs to a SIEM (Entra diagnostic settings in Azure)
- AD FS extranet lockout and endpoint lockdown, and access to servers running identity components (on-premises)
- Azure EA portal access and testing strategy for changes (process, not tenant settings)

## Scripts

### Agent ID

| Script | What it does | Replaces |
| --- | --- | --- |
| [Disable-StaleAgentIdentities.ps1](Agent%20ID/Disable-StaleAgentIdentities.ps1) | Disables stale Entra Agent ID objects: agent identities (service principals) and agent users (user accounts) with no sign-in for a set number of days, and blueprint principals with no active agents. Works from a reviewed Get-StaleAgentIdentities.ps1 report or finds them live. Never deletes and never touches blueprints. Runs interactively or as an Azure Automation runbook with a managed identity. |  |
| [Get-AgentIdentities.ps1](Agent%20ID/Get-AgentIdentities.ps1) | Inventories every Entra Agent ID object, separated by type: agent identity blueprints, blueprint principals, agent identities (service principals), agent users (user accounts) and Copilot Studio agent apps, with their parent, sponsors and last sign-in. | Agent 365\Get Agent Related Service Principals, Agent 365\Get agent related user identities and Applications\get-EntraCopilotServicePrincipals |
| [Get-StaleAgentIdentities.ps1](Agent%20ID/Get-StaleAgentIdentities.ps1) | Finds stale Entra Agent ID objects and calls out each type separately: agent identities (service principals), agent users (user accounts tied to an agent identity), blueprint principals with no active agents, and blueprints that have no principal in this tenant. |  |

### Applications

| Script | What it does | Replaces |
| --- | --- | --- |
| [Disable-StaleApps.ps1](Applications/Disable-StaleApps.ps1) | Disables enterprise apps (service principals) with no sign-in activity for a set number of days, either from a reviewed Get-StaleApps.ps1 report or by finding them live. Disabling blocks sign-ins and tokens but keeps the app, so it can be turned back on. Runs interactively or as an Azure Automation runbook with a managed identity. |  |
| [Get-AppAssignments.ps1](Applications/Get-AppAssignments.ps1) | Shows how each enterprise app is assigned: whether assignment is required, how many users and groups are assigned directly, and whether broad groups like All Users are used, so apps assigned to individuals can be moved to groups. |  |
| [Get-AppCredentialChanges.ps1](Applications/Get-AppCredentialChanges.ps1) | Shows who added or changed certificates and secrets on app registrations and service principals, from the audit log. | Logs\whoAddedCredstoSPAPP |
| [Get-AppCredentials.ps1](Applications/Get-AppCredentials.ps1) | Reports every certificate and client secret on app registrations and service principals, with expiry, lifetime and whether it is long-lived. | get-AllAppCredentials and createAADAPPandSPCredentialReport |
| [Get-AppInventory.ps1](Applications/Get-AppInventory.ps1) | Inventories every enabled enterprise app with its sign-in type (SAML, OIDC, password, desktop, app proxy, OAuth2), last sign-in, 30-day sign-in count, owners and whether Entra recommends removing it as unused. | get-EntraApplicationsDetails, get-SPSignInActivity, get-EntraDesktopApplication, get-EntraSAMLApplications, get-StaleAppsfromEntra, get-StaleAppFromRecommendation and Backup\export-ServicePrincipals |
| [Get-AppPermissions.ps1](Applications/Get-AppPermissions.ps1) | Reports every application (app role) and delegated (OAuth2) permission granted to service principals, with optional filters for Exchange, SharePoint, Azure AD Graph and ReadWrite permissions. | the old get-AllAppAssignedPermissions, get-AllAppDelegatedPermissions, get-assignedEXOPerms, get-assignedSPOPerms, get-delegatedEXOPerms, get-delegatedSPOPerms, get-graphAssignedPermissions, get-AppWithEXOFullAccessPerm, get-ADGraphApplications, get-SPToMuchPerms, export-ApplicationConsents, export-ApplicationRoleAssignments and the createAAD*PermissionReport scripts |
| [Get-AppProvisioningStatus.ps1](Applications/Get-AppProvisioningStatus.ps1) | Lists every enterprise app that has automatic user provisioning set up, with the job status, last run, quarantine state and error counts, so failing or quarantined provisioning can be fixed. |  |
| [Get-AppProxyApps.ps1](Applications/Get-AppProxyApps.ps1) | Lists every application published through Microsoft Entra application proxy with its external and internal URL, pre-authentication type, connector group and single sign-on mode, and flags apps that use passthrough (no Entra pre-authentication). |  |
| [Get-MicrosoftAppsWithOwners.ps1](Applications/Get-MicrosoftAppsWithOwners.ps1) | Finds Microsoft first-party service principals that have owners assigned. Owners can add credentials to these apps and use their permissions. | get-BuiltinAPPOwners and AzureADModule\get-builtinAppwOwnerAssigned |
| [Get-StaleApps.ps1](Applications/Get-StaleApps.ps1) | Finds enabled enterprise apps with no sign-in activity (user or app-only) for a set number of days, plus apps Entra recommends removing as unused, with owners and credentials so owners can be asked before the app is disabled. |  |
| [Remove-ExpiredAppSecrets.ps1](Applications/Remove-ExpiredAppSecrets.ps1) | Removes client secrets that expired more than a set number of days ago from app registrations and service principals. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Authentication Methods

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-HardwareOathTokens.ps1](Authentication%20Methods/Add-HardwareOathTokens.ps1) | Uploads hardware OATH tokens to Entra ID, one at a time or in bulk from a CSV, and can assign each token to a user. | Hardware Oath Token\upload-HardwareOathToken |
| [Enable-HardwareOathToken.ps1](Authentication%20Methods/Enable-HardwareOathToken.ps1) | Activates a hardware OATH token that is assigned to a user, using a code shown on the token. | Hardware Oath Token\activate-UserHardwareOathToken |
| [Get-AuthMethodsPolicy.ps1](Authentication%20Methods/Get-AuthMethodsPolicy.ps1) | Shows which authentication methods are turned on in the Authentication methods policy, who each one targets, the migration state from the legacy MFA and SSPR policies, and the registration campaign settings. |  |
| [Get-MfaRegistration.ps1](Authentication%20Methods/Get-MfaRegistration.ps1) | Reports MFA, SSPR and passwordless registration for members or guests, and flags users who have phone numbers or alternate emails on their account but no registered methods (prepopulated). | create-AADUserMFAReport, create-AADGuestMFAReport, create-AADWH4BRegisteredUsers, get-HybridUserMFAandSSPRState and get-UserSMSPrepopulated |
| [Get-PerUserMfaState.ps1](Authentication%20Methods/Get-PerUserMfaState.ps1) | Lists users who still have legacy per-user MFA turned on (enabled or enforced), which should be replaced with Conditional Access policies. |  |
| [Get-PhoneSignInUsers.ps1](Authentication%20Methods/Get-PhoneSignInUsers.ps1) | Lists users who have a phone number set as a sign-in identity (identities issuer "phone"). | MFA\Get-PhoneIssuer |
| [Get-StaleAuthMethods.ps1](Authentication%20Methods/Get-StaleAuthMethods.ps1) | Finds stale authentication methods: registered methods (Authenticator, phone, FIDO2, Windows Hello, software and hardware OATH, email) not used for a set number of days, and hardware OATH tokens that are not assigned to anyone. |  |
| [Get-UserAuthMethods.ps1](Authentication%20Methods/Get-UserAuthMethods.ps1) | Lists every registered authentication method per user with its details: phone numbers and SMS sign-in state, Microsoft Authenticator app version and device, and when each method was last used. | get-phonemethods, get-SMSSignin, get-authenticatorversion and get-UserAuthMethodLastUsedDate |
| [New-TemporaryAccessPass.ps1](Authentication%20Methods/New-TemporaryAccessPass.ps1) | Creates a Temporary Access Pass for one or more users so they can sign in and register passwordless or MFA methods (new hires, lost phones, account recovery). The pass is shown on screen once and never written to disk. |  |
| [Remove-HardwareOathToken.ps1](Authentication%20Methods/Remove-HardwareOathToken.ps1) | Removes a hardware OATH token from a user so it can be reassigned or retired. | Hardware Oath Token\delete-HardwareOathTokenFromUser (which called the wrong URL) |
| [Remove-StaleAuthMethods.ps1](Authentication%20Methods/Remove-StaleAuthMethods.ps1) | Removes stale authentication methods (not used for a set number of days) from users, never removing a user's last MFA method, and can delete unassigned hardware OATH tokens. Works from a reviewed Get-StaleAuthMethods.ps1 report or finds them live. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Conditional Access Policy

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-BreakGlassExclusions.ps1](Conditional%20Access%20Policy/Add-BreakGlassExclusions.ps1) | Makes sure the emergency access (break glass) accounts are excluded from every Conditional Access policy and adds them where they are missing. Runs interactively or as an Azure Automation runbook with a managed identity. | add-BreakGlasstoConditionalAccessPolicyExclusion |
| [Add-ExclusionGroups.ps1](Conditional%20Access%20Policy/Add-ExclusionGroups.ps1) | Creates one exclusion group per Conditional Access policy inside a restricted administrative unit and adds each group to its policy's exclusions, so exclusions are managed through groups instead of the policies. | add-ExclusionGroupALLCAP |
| [Compare-CABaseline.ps1](Conditional%20Access%20Policy/Compare-CABaseline.ps1) | Compares the tenant's Conditional Access policies against Microsoft's common policy templates and CIS benchmark policies, and lists which existing policies (if any) satisfy each one. | compare-baselineconditionalaccesspoliciestoexistingpolicies and its duplicate Backup\export-ConditionalAccessPolicyMapping |
| [Export-CAPoliciesToCsv.ps1](Conditional%20Access%20Policy/Export-CAPoliciesToCsv.ps1) | Flattens every Conditional Access policy into one CSV row with a column for every setting, by walking each policy object, so new policy settings show up without code changes. | exportConditionalAccessPolicytoCSV |
| [Get-CAExclusions.ps1](Conditional%20Access%20Policy/Get-CAExclusions.ps1) | Lists everyone excluded from each Conditional Access policy, expanding excluded groups (including nested groups) and roles down to the actual users, so exclusions can be reviewed. | exportConditionalAccessExclusions and createConditionalAccessPolicyexclusionstats |
| [Get-CAPolicyReport.ps1](Conditional%20Access%20Policy/Get-CAPolicyReport.ps1) | Reports each Conditional Access policy with how many users it targets and excludes (through users, groups, roles and guests), its apps, conditions, grant and session controls. | count-usersperconditionalaccesspolicy and Backup\export-ConditionalAccessPolicy |
| [Get-StaleCAObjects.ps1](Conditional%20Access%20Policy/Get-StaleCAObjects.ps1) | Finds stale objects in Conditional Access: users, groups, roles, apps and named locations that policies still point to but no longer exist, named locations no policy uses, and policies that have been turned off for a set number of days. |  |
| [Import-RecommendedCAPolicies.ps1](Conditional%20Access%20Policy/Import-RecommendedCAPolicies.ps1) | Imports recommended Conditional Access policies from this repo's JSON file into the tenant in report-only mode, one at a time from a menu or all at once. | Import-AADRecommendedConditionalAccessPolicies |
| [New-TorNamedLocations.ps1](Conditional%20Access%20Policy/New-TorNamedLocations.ps1) | Creates untrusted IP named locations from a public list of Tor exit nodes (1,000 addresses per location), for use in a Conditional Access block policy. | exampletocreatebadiplocations |
| [Remove-StaleCAObjects.ps1](Conditional%20Access%20Policy/Remove-StaleCAObjects.ps1) | Cleans up stale Conditional Access objects: removes references to deleted users, groups, roles, apps and named locations from policies, and deletes named locations no policy uses. Works from a reviewed Get-StaleCAObjects.ps1 report or finds them live. Never deletes or turns off a policy. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Devices

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-DeviceKeyCoverage.ps1](Devices/Get-DeviceKeyCoverage.ps1) | Checks every enabled Windows device for a Windows LAPS local admin password backup and a BitLocker recovery key in Entra ID, so devices that couldn't be recovered can be found before they're needed. |  |
| [Get-DeviceReport.ps1](Devices/Get-DeviceReport.ps1) | Reports every device in Entra ID with its join type, OS, compliance, last sign-in and owner, and flags stale devices. | Devices\AzureADModule\AzureADDeviceScriptCollection and getAADDevicesStatus |
| [Get-DisabledDevicesInUse.ps1](Devices/Get-DisabledDevicesInUse.ps1) | Finds disabled devices that people are still trying to use, from sign-ins that failed with error 135011 (device disabled), so they can be re-enabled or the users helped before devices are deleted. | Devices\AzureADModule\GetDisabledAADDevicesStillInUse |
| [Get-StaleDevices.ps1](Devices/Get-StaleDevices.ps1) | Finds devices with no activity for a set number of days and says how to remediate each one: disable then delete in Entra, clean up in Active Directory for hybrid joined devices, or leave Windows Autopilot devices alone. |  |
| [Remove-StaleDevices.ps1](Devices/Remove-StaleDevices.ps1) | Cleans up stale devices the way Microsoft recommends: first disables devices with no activity, then deletes devices that are already disabled and still inactive. Skips hybrid joined (synced) and Windows Autopilot devices. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Domains

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-DomainUsage.ps1](Domains/Get-DomainUsage.ps1) | Lists the registered domains and every place each domain is used on users, deleted users, groups, contacts, app registrations and service principals, which is needed before a domain can be removed. | Custom Domain\inventory-everyobjectdomainattribute and Backup\export-RegisteredDomains |
| [Get-StaleDomains.ps1](Domains/Get-StaleDomains.ps1) | Finds stale custom domains: domains that were added but never verified, and verified domains that no user, group or app uses any more. |  |
| [Remove-StaleDomains.ps1](Domains/Remove-StaleDomains.ps1) | Deletes stale custom domains: unverified domains and, with -IncludeVerified, verified domains nothing uses. Never touches the default, initial or federated domains or any domain still in use. Works from a reviewed Get-StaleDomains.ps1 report or finds them live. |  |

### Groups

| Script | What it does | Replaces |
| --- | --- | --- |
| [Backup-CloudGroups.ps1](Groups/Backup-CloudGroups.ps1) | Backs up cloud-only security groups to JSON: assigned members, dynamic membership rules, owners and app role assignments, so a deleted or changed group can be rebuilt. | backup-CloudSecurityGroupMembers, backup-DynamicSecurityGroupMemberShipRules and backup-GroupsAppRoleAssignment |
| [Export-GroupMemberships.ps1](Groups/Export-GroupMemberships.ps1) | Exports the security groups every member user, guest and group belongs to, including nested membership, as three CSV files. | export-groupsecuritymembership and Backup\export-GroupMemberShips |
| [Get-GroupAppRoleAssignments.ps1](Groups/Get-GroupAppRoleAssignments.ps1) | Lists the apps and app roles every group is assigned to, to find broad groups (like All Users) that grant access to apps. | AzureADModule\getAADAllUsersGroupAppRoleAssignment |
| [Get-GroupReport.ps1](Groups/Get-GroupReport.ps1) | Reports every group with its type, member and owner counts, licenses, dynamic rule state and duplicate names, so empty, ownerless, duplicate and broken dynamic groups can be found in one file. | get-GroupMemberCount, get-EmptySecurityGroups, get-SyncedEmptySecurityGroups, get-OwnerlessSecurityGroups, get-OwnerlessUnifiedGroups, get-DynamicGroupProcessingStateNotOn, get-memberofdynamicgroups, find-DuplicateGroups, Backup\export-Groups and the AzureADModule scripts getAADGroupsMissingOwner, getMemberlessAADGroups, getMemberlessAADUnifiedGroups, getAADLicensedGroups and getAADUnifiedGroupsMissingLifecyclePolicies |
| [Get-StaleGroups.ps1](Groups/Get-StaleGroups.ps1) | Finds stale groups: cloud groups with no members and Microsoft 365 groups that have not been renewed for a set number of days, and flags groups that are still in use (Conditional Access, app assignments, licenses, roles) so they are not removed by mistake. |  |
| [Remove-StaleGroups.ps1](Groups/Remove-StaleGroups.ps1) | Deletes stale cloud groups that are empty and not used anywhere (not in Conditional Access, not role-assignable, no licenses, no app assignments), after saving a JSON backup of each group. Works from a reviewed Get-StaleGroups.ps1 report or finds them live. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Guest

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-GuestSponsors.ps1](Guest/Add-GuestSponsors.ps1) | Sets the person who invited each guest as the guest's sponsor, using the "Invite external user" audit events. Runs interactively or as a daily Azure Automation runbook with a managed identity. | add-AADSponsoronGuest |
| [Get-GuestAccess.ps1](Guest/Get-GuestAccess.ps1) | Exports what guests have access to and own: group memberships, app role assignments and owned objects, for review or as a backup before removing guests. | backup-GuestGroupMembership, backup-GuestAppRoleAssignments and find-GuestOwnedObjects |
| [Get-GuestReport.ps1](Guest/Get-GuestReport.ps1) | Reports every guest with invite state, last sign-in, sponsors and sign-in issuer, and can check whether each guest's home tenant is viral (unmanaged). | create-GuestReport, create-GuestReportV2, create-GuestIsViralReport, create-GuestIsViralReportV2, get-GuestSponsors, get-MGEntraStaleGuest and Backup\export-Guests |
| [Get-StaleGuests.ps1](Guest/Get-StaleGuests.ps1) | Finds guests that have not signed in for a set number of days and guests that never accepted their invitation, with sponsors and the reason each is stale. |  |
| [Remove-StaleGuests.ps1](Guest/Remove-StaleGuests.ps1) | Deletes guests that have not signed in for a set number of days or never accepted their invitation, either from a reviewed Get-StaleGuests.ps1 report or by finding them live. Runs interactively or as an Azure Automation runbook with a managed identity. Deleted guests stay in the recycle bin for 30 days. |  |
| [Reset-GuestRedemption.ps1](Guest/Reset-GuestRedemption.ps1) | Resets the redemption status of guests so they can sign in again with a different account or method (for example after leaving their home company or when their home tenant is a viral tenant) without losing their group memberships and app access. |  |

### Hybrid Identity

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AdfsAppMigration.ps1](Hybrid%20Identity/Get-AdfsAppMigration.ps1) | Lists the AD FS relying parties seen by Entra Connect Health with their sign-in volume and whether each one is ready to move to Microsoft Entra ID, to plan the AD FS application migration. |  |
| [Get-HybridHealth.ps1](Hybrid%20Identity/Get-HybridHealth.ps1) | Checks the health of hybrid identity: last directory sync and how long ago it ran, sync features such as password hash sync and writeback, and every pass-through authentication agent, private network (application proxy) connector and provisioning agent with its version, status and whether its group has at least two for redundancy. |  |
| [Get-SyncAccountSignIns.ps1](Hybrid%20Identity/Get-SyncAccountSignIns.ps1) | Lists the IP addresses and apps used by Directory Synchronization Accounts (Entra Connect sync accounts), to confirm they only sign in from the sync servers. | Azure AD Connect\GetSyncAccountIPs and getSyncAccountSigninApps |
| [Get-SyncErrors.ps1](Hybrid%20Identity/Get-SyncErrors.ps1) | Lists users, groups and contacts with Entra Connect synchronization errors (for example duplicate proxy addresses or UPNs) and how long each error has been there, so errors older than 100 days can be cleaned up. |  |

### Identity Governance

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AccessPackages.ps1](Identity%20Governance/Get-AccessPackages.ps1) | Lists every entitlement management catalog and access package with its assignment policies (who can request, whether approval is required, how long access lasts, whether access reviews run) and how many active assignments it has. |  |
| [Get-AccessReviewCoverage.ps1](Identity%20Governance/Get-AccessReviewCoverage.ps1) | Lists every access review and shows what still has no regular review: guests, privileged roles, groups used in Conditional Access exclusions, and apps that require assignment, as the operations guide recommends. |  |
| [Get-LifecycleWorkflows.ps1](Identity%20Governance/Get-LifecycleWorkflows.ps1) | Lists every lifecycle workflow (joiner, mover and leaver automation) with whether it's on and scheduled, its tasks, and the results of its recent runs, including failed users. |  |

### Identity Protection

| Script | What it does | Replaces |
| --- | --- | --- |
| [Dismiss-RiskyUsers.ps1](Identity%20Protection/Dismiss-RiskyUsers.ps1) | Dismisses user risk that is older than a set number of days for the chosen risk levels. Runs interactively or as an Azure Automation runbook with a managed identity. | dismiss-IdentityProtectionRiskyUsers |
| [Get-RiskDetections.ps1](Identity%20Protection/Get-RiskDetections.ps1) | Exports Identity Protection risk detections for users (such as leaked credentials, unfamiliar sign-in properties and impossible travel) for a set number of days, for triage and investigation. |  |
| [Get-RiskyServicePrincipals.ps1](Identity%20Protection/Get-RiskyServicePrincipals.ps1) | Lists workload identities (service principals) that Identity Protection marks as risky, with their risk detections, so compromised apps can be investigated. |  |
| [Get-RiskyUsers.ps1](Identity%20Protection/Get-RiskyUsers.ps1) | Reports users Identity Protection currently marks as at risk, with risk level, when the risk was last updated and whether the user changed their password since. | export-IdentityProtectionAllRiskyUsers and Backup\export-RiskyUsers |

### Intune

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-IntuneRoleAssignments.ps1](Intune/Get-IntuneRoleAssignments.ps1) | Lists every Intune role assignment with the groups and users that hold it and the permissions the role grants. | Intune\get-IntuneRoles (which showed results in Out-GridView) |

### Licenses

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-LicenseReport.ps1](Licenses/Get-LicenseReport.ps1) | Reports license use: each subscription's purchased and assigned counts, every user license assignment (direct or through a group) with any assignment error, and groups that have members in a license error state. |  |
| [Get-StaleLicenses.ps1](Licenses/Get-StaleLicenses.ps1) | Finds licenses that are wasted: licenses assigned to disabled accounts and to accounts that have not signed in for a set number of days, and says whether each one is assigned directly or through a group. |  |
| [Remove-StaleLicenses.ps1](Licenses/Remove-StaleLicenses.ps1) | Removes directly assigned licenses from disabled accounts and accounts that have not signed in for a set number of days, from a reviewed Get-StaleLicenses.ps1 report or found live. Licenses that come from a group are left alone. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Logs

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-AppSignInSummary.ps1](Logs/Get-AppSignInSummary.ps1) | Shows the number of successful and failed sign-ins for each application over the last 7 or 30 days. | exportAADSummaryforApplicationSignins |
| [Get-CriticalAuditEvents.ps1](Logs/Get-CriticalAuditEvents.ps1) | Pulls high-impact audit events, like federation and sync changes, permanent role assignments, new credentials on apps and Conditional Access changes, into one CSV. | Security\gatherAzureADAuditLogs |
| [Get-ExternalTenantSignIns.ps1](Logs/Get-ExternalTenantSignIns.ps1) | Lists the other tenants your users sign in to (as guests or through cross-tenant access), with the tenant name and the apps used. | Users\retrieve-ExternalTenantsUsedByUsers |
| [Get-LegacyAuthSignIns.ps1](Logs/Get-LegacyAuthSignIns.ps1) | Finds sign-ins that used legacy (basic) authentication clients such as IMAP, POP, ActiveSync and older Office clients, grouped by user, app and client. | findBasicAuthExchangeOnline, findBasicAuthSharepointOnline and findBasicAuthSkypeforBusinessOnline |
| [Get-LegacyTlsSignIns.ps1](Logs/Get-LegacyTlsSignIns.ps1) | Finds sign-ins that used legacy TLS (TLS 1.0, 1.1 or 3DES), so the clients can be updated before they stop working. | getlegacytls |
| [Get-SignInLocations.ps1](Logs/Get-SignInLocations.ps1) | Summarizes sign-ins by country and region, with how many users and failures come from each, to find traffic from places where there's no business reason to sign in and block them with a location-based Conditional Access policy. |  |
| [Get-UserSignIns.ps1](Logs/Get-UserSignIns.ps1) | Pulls sign-in logs for one user or for a specific error code, including the Conditional Access policies that applied, for troubleshooting and lockout investigations. | viewAADUserSignins, viewAADUserSigninwithCAP and findAccountsWithLockoutEvents (use -ErrorCode 50053) |

### Roles and PIM

| Script | What it does | Replaces |
| --- | --- | --- |
| [Add-GroupsToRoles.ps1](Roles%20and%20PIM/Add-GroupsToRoles.ps1) | Creates role-assignable security groups from a CSV of roleName and groupName pairs and gives each group a permanent active assignment to its directory role, so PIM for Groups can control who is in the role. | PIM\addGrouptoRoleinPIM |
| [Export-PimSettings.ps1](Roles%20and%20PIM/Export-PimSettings.ps1) | Exports the PIM settings (role management policy rules) for every directory role and every group onboarded to PIM for Groups, one JSON file per role or group plus a summary CSV. | PIM\export-PIMSettings and the empty PIM\backup-PIMDirectoryRoleSettings |
| [Get-AdminUnits.ps1](Roles%20and%20PIM/Get-AdminUnits.ps1) | Lists every administrative unit with its membership type, member count, whether management is restricted, and the admins whose roles are scoped to it. |  |
| [Get-CustomRoles.ps1](Roles%20and%20PIM/Get-CustomRoles.ps1) | Lists every custom directory role with its permissions, whether any permission is privileged, and who holds it (active and eligible), so custom roles that grant too much or are unused can be cleaned up. |  |
| [Get-PrivilegeEscalationPaths.ps1](Roles%20and%20PIM/Get-PrivilegeEscalationPaths.ps1) | Finds the users, groups and apps that can change credentials, change group membership or elevate privileges, through Microsoft Graph app permissions, directory roles or ownership of those apps. | Security\Get-AADObjectsCanChangeCred, Get-AADObjectsCanChangeGroupMembership, Get-AADObjectsCanElevatePriv, Roles\AzureADModule\roleAbleTo*, and Applications\get-AppsandOwnersCanChangeAllGroupMembership / get-AppsandOwnersCanAssignAppRoles |
| [Get-RoleAuditEvents.ps1](Roles%20and%20PIM/Get-RoleAuditEvents.ps1) | Pulls audit events about directory roles and their members: role membership and PIM changes, changes made to admin accounts, and changes made by admin accounts. | Roles\auditRoleMembershipChanges, PIM\auditPIMRoleChanges, getAADChangesToGlobalAdmins, getAADChangesbyGlobalAdmins and Security\GatherRoleMemberChanges |
| [Get-RoleMemberAppliedPolicies.ps1](Roles%20and%20PIM/Get-RoleMemberAppliedPolicies.ps1) | Shows which Conditional Access policies were applied to the sign-ins of privileged role members, to spot admins who are not covered. | Roles\getAADRoleCAPused |
| [Get-RoleMembers.ps1](Roles%20and%20PIM/Get-RoleMembers.ps1) | Reports every active and eligible Entra directory role member, expanding role-assignable groups and PIM for Groups, with account state, last sign-in and MFA registration. | ExportAADDirectoryRoleMembers, getAzureADPrivRoleMembers, collectAzureADRoleMembersMFAStatus, getAADInactiveRoleMembers, createAADDirectoryRoleMemberReport, Export-AADRoleMembers, export-PIMROLEMembersstate, export-HighlyPrivAccountsMFA, exportAADPIMRoleMembers, RetrieveAdminsforKQL, Backup\export-DirectoryRoleMembership and Backup\export-PIMDirectoryRoles |
| [Get-StaleRoleAssignments.ps1](Roles%20and%20PIM/Get-StaleRoleAssignments.ps1) | Finds stale directory role assignments: active or eligible assignments held by disabled accounts, by users or apps that have not signed in for a set number of days, and eligible assignments that were never activated in that time. |  |
| [Remove-StaleRoleAssignments.ps1](Roles%20and%20PIM/Remove-StaleRoleAssignments.ps1) | Removes stale directory role assignments (held by disabled accounts, accounts with no sign-in, or eligible assignments never activated) through PIM admin remove requests, from a reviewed Get-StaleRoleAssignments.ps1 report or found live. Never touches Global Administrator, group assignments or the accounts you exclude. Runs interactively or as an Azure Automation runbook with a managed identity. |  |

### Security

| Script | What it does | Replaces |
| --- | --- | --- |
| [Get-EntraRecommendations.ps1](Security/Get-EntraRecommendations.ps1) | Lists Microsoft Entra recommendations (the tenant's built-in best-practice findings) with their status, priority and how many resources each one affects. |  |
| [Get-HealthAlerts.ps1](Security/Get-HealthAlerts.ps1) | Lists Microsoft Entra health monitoring alerts, such as spikes in MFA failures, Conditional Access blocks or device compliance failures, with their state and impact. |  |
| [Get-SecureScore.ps1](Security/Get-SecureScore.ps1) | Exports Microsoft Secure Score recommendations with rank, score impact, points achieved, status, category and product, in the same layout as the Defender portal export. | Microsoft Secure Score\get-MicrosoftSecureScorefromGraph |
| [Get-SecurityAlerts.ps1](Security/Get-SecurityAlerts.ps1) | Exports Microsoft Defender XDR and Entra ID Protection security alerts from the last set number of days. | Security Alerts\gather-graphSecurityAlerts, which used the retired legacy alerts API |

### Tenant

| Script | What it does | Replaces |
| --- | --- | --- |
| [Export-TenantSettings.ps1](Tenant/Export-TenantSettings.ps1) | Backs up the main tenant-wide settings to JSON (organization, authorization policy, sync features, authentication methods, admin consent, staged rollout, cross-tenant defaults, security defaults) and licenses to CSV. | getAADSettings (MSOnline) and Backup\export-Settings |
| [Get-CrossTenantAccess.ps1](Tenant/Get-CrossTenantAccess.ps1) | Reports cross-tenant access settings for the default and for every partner organization: B2B collaboration and B2B direct connect inbound and outbound, which MFA and device claims are trusted, automatic invitation redemption, and cross-tenant sync. |  |
| [Get-TenantLookup.ps1](Tenant/Get-TenantLookup.ps1) | Looks up the Entra tenant behind an email address or domain: tenant ID, name, default domain, namespace type, and whether it is a viral (unmanaged) tenant. | Tenant\istenantviral and Tenant\lookup-tenant |
| [Test-TenantSettings.ps1](Tenant/Test-TenantSettings.ps1) | Checks tenant-wide settings against the Microsoft Entra operations reference guide (user and group settings, consent, guest access, password protection, password hash sync, notification contacts, emergency access accounts, named locations and legacy authentication blocking) and marks each one Pass or Review. |  |

### Users

| Script | What it does | Replaces |
| --- | --- | --- |
| [Disable-StaleUsers.ps1](Users/Disable-StaleUsers.ps1) | Disables cloud-only member accounts that have not signed in for a set number of days, either from a reviewed Get-StaleUsers.ps1 report or by finding them live. Runs interactively or as an Azure Automation runbook with a managed identity. |  |
| [Get-StaleUsers.ps1](Users/Get-StaleUsers.ps1) | Finds member accounts that have not signed in (interactively or non-interactively) for a set number of days and says how to remediate each one: disable in Entra for cloud-only accounts, disable in Active Directory for synced accounts. |  |
| [Get-UserDirectReports.ps1](Users/Get-UserDirectReports.ps1) | Lists everyone who reports to a manager, directly or through other managers, all the way down the org chart. | get-AADUsersDirectReports |
| [Get-UserReport.ps1](Users/Get-UserReport.ps1) | Reports every member user with sign-in activity, password age and hybrid sync state, and flags stale accounts, old passwords and synced users that stopped syncing. | create-AADMGUserReport, create-AADUserSigninreport, find-AADMGUsersStaleLastSignIn, find-AADMGUserStalePWD, find-usersnotsyncing, Get-EntraHybridUserPasswordChange, getAADUserSignons, Backup\export-Users and GCC\exportGCCAADUsers (pick USGov or USGovDoD for government clouds) |
| [Get-UsersWithPersonalEmail.ps1](Users/Get-UsersWithPersonalEmail.ps1) | Finds member users whose alternate email addresses (otherMails) are personal mailboxes such as Gmail, Outlook.com or Yahoo, which can be used for password reset. | Security\findAADUsersPersonalAltEmail |
| [Revoke-UserAccess.ps1](Users/Revoke-UserAccess.ps1) | Cuts off a user in an emergency (for example a compromised account or an urgent termination): disables the account, revokes every refresh token and session, and disables the user's registered devices. |  |

## Other folders

- **Maintenance Task** - Azure Automation runbooks that need no modules (they get a token from the managed identity). See its [README](Maintenance%20Task/README.md) for setup.
- **Log Analytics** - KQL queries for Log Analytics and Sentinel.
- **_Archive** - older scripts that can't run on Microsoft Graph alone (Azure RBAC with the Az module, on-premises AD, local registry checks, the China cloud). Kept for reference, not maintained.
- **screen** - Conditional Access screenshots.
