# How to write PowerShell in this repo

These are the owner's rules. Follow them in every script you add or change.

- Use straight Microsoft Graph calls: `Connect-MgGraph` and `Invoke-MgGraphRequest` only (module Microsoft.Graph.Authentication). Don't require any other module or cmdlet (no `Get-Mg*`, `New-Mg*`, Entra or Az modules).
- Use the Microsoft Graph **beta** endpoint (`https://graph.microsoft.com/beta`) for every call. It usually has more properties and APIs than v1.0.
- Keep it simple. Don't over-complicate the code.
- Never use `+=`. Let the pipeline collect output, or wrap it in `@( )`.
- Don't create custom objects (`[pscustomobject]@{}`, `New-Object PSObject`, classes). Keep data in the pipeline and shape it with `Select-Object` calculated properties (`@{ n = "Name"; e = { ... } }`).
- Use functions for each step, and make them pipeline-friendly (`process { }` blocks) where it fits.
- Follow `@odata.nextLink` for every collection.
- Ask which cloud to connect to. Add `[ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment`; if it's empty, list those clouds from `Get-MgEnvironment` (same module), ask with `Read-Host` into a separate variable (the ValidateSet rejects an empty answer), and default to Global. Build every URL from that cloud's `GraphEndpoint` (never hard-code `graph.microsoft.com`) and pass `-Environment $Environment` to `Connect-MgGraph`.
- Never put tenant IDs, object IDs or email addresses in the repo. Use placeholders like `"<person UPN>"`.

## Folders

- Put each script in the folder for the object type it works on (Users, Guest, Agent ID, Groups, Applications, Devices, Roles and PIM, Conditional Access Policy, and so on). Don't add scripts to the repo root, and delete folders that end up empty.
- In `Agent ID`, always say which kind of object each row is: `Blueprint` (the agent identity blueprint application), `BlueprintPrincipal`, `AgentIdentity` (the agent's service principal) or `AgentUser` (the agent's user account). Leave agent users out of the Users scripts and agent service principals out of the Applications scripts.
- Don't add a second script that does the same job as an existing one. Add a parameter or a column to the existing script instead.
- Folders that only hold reports or settings (Hybrid Identity, Identity Governance, Intune, Logs, Security, Tenant) don't need stale scripts.
- Each object type folder has a stale object report (`Get-Stale<Type>.ps1`) and a remediation script (`Disable-Stale<Type>.ps1` or `Remove-Stale<Type>.ps1`). Remediation scripts take the reviewed report with `-CsvPath`, check each object again before changing it, support `-WhatIf`, have a `-MaxRemovals` limit and take `-Identity` to run as a runbook.
- List every new script in README.md. If it covers a task in the Microsoft Entra operations reference guide, add it to the guide coverage table too.

## Exceptions

### Maintenance Task folder

The scripts in `Maintenance Task` are Azure Automation runbooks that many people copy straight into a runbook, so they must not need **any** module, not even Microsoft.Graph.Authentication. In that folder only:

- Get a token from the Automation account's managed identity (`$env:IDENTITY_ENDPOINT` with the `X-IDENTITY-HEADER` and `Metadata` headers) and call Microsoft Graph with `Invoke-RestMethod` and a `Bearer` token. Don't use `Connect-MgGraph`, `Invoke-MgGraphRequest` or `Get-MgEnvironment`.
- Runbooks can't prompt, so don't use `Read-Host`. Take the Graph endpoint as a parameter instead, like `[string]$GraphEndpoint = "https://graph.microsoft.com"` (`https://graph.microsoft.us` for USGov, `https://dod-graph.microsoft.us` for USGovDoD), and build every URL and the token resource from it.
- Handle throttling (HTTP 429) by waiting for the `Retry-After` time and trying again.
- Every other rule above still applies: beta endpoint, follow `@odata.nextLink`, no `+=`, no custom objects, functions per step, a safety limit on changes, and the script header below.

### Folders these rules don't cover

- `Log Analytics` holds KQL queries, not PowerShell. It will move to another repo; leave it alone.
- `_Archive` holds old scripts that can't follow these rules (Az module, on-premises AD, registry, China cloud). Don't update them; write a new script in the right folder instead.

## Script header


Start every script with a `<#PSScriptInfo #>` block, the way the owner's [Azure_Active_Directory](https://github.com/chadmcox/Azure_Active_Directory) scripts do. Put it above the comment-based help (`<# .SYNOPSIS ... #>`) and the `param()` block.

- **.VERSION**: the year and month, like `2026.10`. Change it when you change the script.
- **.GUID**: a new GUID for each new script (`[guid]::NewGuid()`). Keep it when you update the script. Never copy one from another script.
- **.AUTHOR**: `Chad Cox` with the blog and GitHub links below. No email address.
- **.COPYRIGHT**: the sample code disclaimer below, word for word.
- **.description**: one line on what the script does, then the Microsoft Learn URL it's based on.

```powershell
<#PSScriptInfo
.VERSION 2026.10
.GUID <new GUID>
.AUTHOR Chad Cox
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
.description
<What the script does, in one line.>
url: <Microsoft Learn page title> - <https://learn.microsoft.com/...>
#>
```
