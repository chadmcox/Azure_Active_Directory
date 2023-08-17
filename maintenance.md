# Entra ID Task List


## Applications and Service Principals

| Task | Script |
| --------------------- | --------------------- |
| Review applications with delegated rights to Exchange Online, goal is to minimize the list of applications with rights to user mail boxes and make sure applications are approved for the business |  |
| Review applications with delegated rights to SharePoint Online, goal is to minimize the list of applications with rights to user mail boxes and make sure applications are approved for the business |  |
| Review applications with assigned rights to Exchange Online, goal is to limit (reduce the number) and protect applications that have rights to every user mailbox.  |  |
| Review applications with assigned rights to SharePoint online, goal is to limit (reduce the number) and protect applications that have rights to site or user onedrive.  |  |
| Review and monitor for applications that have been assigned the permission to modify group membership, goal is to minimize and protect those applications.  |  |
| Review and monitor for applications that have been assigned the permission to assign credentials, goal is to minimize and protect those applications.  |  |
| Review and monitor for applications that have been assigned the permission to do role assignments, goal is to minimize and protect those applications.  |  |
| Review and monitor for Microsoft built-in (first party) applications having owners assigned, Owners have the ability to perform role assignments and add credentials to the applications that could be used against the applications  |  |
| Review and monitor for applications that have been given readwrite permissions.  Owners of these applications should be considered sensitive.  For these type of applications the goal is not to use owner assignments.  |  |
| Find and disable applications that are considered stale. The recommendations feature is a great place to start. |  |
| Require all applications that users can log into require assignments to prevent accidental access by guest users.  |  |
| Monitor for and replace credentials that are about to expire.    |  |
| Monitor for applications that create user accounts.    |  |
| Operationalize consent workflow request  |  |

## Directory Roles

| Task | Script |
| --------------------- | --------------------- |

## Guest (B2B)

| Task | Script |
| --------------------- | --------------------- |
| Review and monitor applications guest are accessing, look for access to unexpected applications like Azure Portal, PowerShell, Devops, HR Apps, Payrole Apps or VPNs. |  |
|  Have a process in place to remove not accepted guest from the tenant after a specific period of time (15-30 days).  Make sure the guest user is not a member of a unified group as it could be to a distribution list and could cause problems.  if using some sort of automation review the logs to make sure it is working as expected. |  |
| Find guest users that haven't logged into the tenant after a period of time and remove them.  (I recommend a remove over a disable because if the remove was done in error the guest just needs to be reinvited.) This can be tricky for otp guest users. |  |

## Users

| Task | Script |
| --------------------- | --------------------- |
| Find cloud users that are stale.  Consider disabling and removing. |  |
| Make sure stale hybrid accounts are not synced to the cloud.  Only sync what is needed to the tenant. |  |
| Review users that appear not to be syncing anymore and remediate. |  |
| Monitor for cloud users being created, if a hybrid environment is in place. |  |
| Monitor for possible brute force against users. |  |
| Monitor for users being locked out frequently. |  |
| Monitor for users potentially experiencing mfa spamming. |  |
| Monitor for users performing several deny's or reporting fraud. |  |

## Groups

| Task | Script |
| --------------------- | --------------------- |
| Find and review unused groups. |  |
| Review and remdiate dynamic groups that are not on. |  |
| Review and remdiate dynamic groups that are in an error state. |  |

## Devices

| Task | Script |
| --------------------- | --------------------- |
| Find and review stale devices. |  |
| Find and remediate not supported operating systems. |  |
| Monitor for devices failing to signin and remediate |  |

## Conditional Access Policies

## Id Protection

| Task | Script |
| --------------------- | --------------------- |
| Find and define unknown trusted networks. This may include setting up zscaler or umbrella as a trusted network. |  |
| Monitor for users registering MFA with a risk. |  |
| Monitor for users changing passwords outside the trusted network to remediate a risk, using a less secure mfa method |  |
| Consider automation to dismiss low and medium risk after 30 days |  |
| Monitor and remediate high user risk |  |
| Review and remediate users being flagged as a risk due to password spray |  |

## Privileged Identity Management

| Task | Script |
| --------------------- | --------------------- |
| Review and remediate PIM role and Group settings. |  |
| Review and make sur directory role members and privileged group members are not permenant. |  |
