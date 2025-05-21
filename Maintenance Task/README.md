
# How to setup and configure Azure Automation Account to run Azure AD Maintenance Scripts

## Create Automation Account
1. Open Azure Portal and Navigate to Automation Accounts
2. Select create
3. In Basic, Select Subscription and Create or use a an existing resource group
4. Enter an automation account name: "AADAutomation"
5. Select the region, click Next
6. In Advanced, Select Sytem Assigned, click Next
7. In Networking, Select Public access, click Next
8. Enter in TAGS based on what is required in your org
9. Then select create
10. Once created, open the newly create Automation Account

## Give the Automation Account Permissions in Graph
1. Open PowerShell
2. Run the following cmdlets

```
#put the name of the automation account in this variable replace 'AADAutomation'
$AzureAccountName = "AADAutomation"

#Install the powershell module if required
install-module microsoft.graph

#Connect to mggraph, may require a user consent
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All", "Directory.AccessAsUser.All"

#retrive the service principal id
$managedspid = (Get-MgServicePrincipal -All | where {$_.DisplayName -eq $AzureAccountName}).id

#this is the appid for graph
$graphResourceId = "00000003-0000-0000-c000-000000000000"

#write all of the required graph scopes in this list.  it may be required to update based on usuage of the automation account
$graphScope = "Reports.Read.All","User.Read.All","Directory.Read.All","Group.Read.All","AuditLog.Read.All","Organization.Read.All","Policy.Read.All",`
    "Device.Read.All","AdministrativeUnit.Read.All","PrivilegedAccess.Read.AzureAD","PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources", `
    "Policy.ReadWrite.ConditionalAccess","Application.Read.All","User.Invite.All","User.ReadWrite.All","IdentityRiskEvent.Read.All","IdentityRiskyUser.ReadWrite.All"

#this creates a list of ID and scope that the cmdlet will be able to read to add the assignments.
$requirePermissions = $graphScope | Find-MgGraphPermission -ExactMatch -PermissionType Application | foreach{@{ID = $_.id; Type = 'Role'}}

#retrieve the graph id that is in the tenant
$msgraphID = (Get-MgServicePrincipal -Filter "appid eq '00000003-0000-0000-c000-000000000000'").Id

#check to see if any assignments exist
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedspid

#this will create new assignments
foreach($approleid in $requirePermissions.id){
    new-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedspid -AppRoleId $approleid  -ResourceId $msgraphID -PrincipalId $managedspid
}

#verify that the assignments are present
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedspid
```

## Create a powershell runbooks
1. Open the newly created Azure Automation Account in the portal
2. In the Process Automation section select Runbooks
3. select Create a runbook
4. Name: enter in a name that is related to what the script will be doing
5. Runbook type: select PowerShell
6. Runtime version: 5.1 (unless the script was created in newer powershell)
7. Select Create
8. In the Edit PowerShell Runbook, Copy the code you would like to run into the editor
9. Save the runbook
10. Select Testpane, and then start to make sure the script is working as expected.  (Note: it takes a few moments to run)
11. Once testing is complete close
12. After all modifications to the script and testing is done select publish and confirm.
13. In the Runbooks properties, select schedule and add a schedule, select the schedule that best fits what is needed
14. Close out the runbooks properties and validate that the new runbook is in a Published Status

This should be all that is neeeded

## Create job that automatically puts the breakglass / emergency accounts as a exclusion in condition access policies
* The script is runbook-addAADBreakGlasstoConditionalAccessPolicy.ps1 [(click here)](https://github.com/chadmcox/Azure_Active_Directory/blob/master/Maintenance%20Task/runbook-addAADBreakGlasstoConditionalAccessPolicy.ps1) and copy code into runbook.
* Update the script / runbook to have the correct guids of the breakglass accounts, update line 36 with the proper guids. if only one breakglass is used, then remove the , and remaining guid.
```
35 #these must be updated with the breakglass account guids.
36 $breakglass_accounts = "948b11fc-5fc4-45dd-91ac-97e38a16372a","d18d12aa-9a08-4d9d-9ffc-67995670d0c0"

```
## Create job that will automatically dismiss at risk users after a specific time frame
* The script is runbook-dismissAIPRiskyUsers.ps1 [Click here](https://github.com/chadmcox/Azure_Active_Directory/blob/master/Maintenance%20Task/runbook-dismissAIPRiskyUsers.ps1) and copy code into runbook
* Consider updating the following lines in the script, default is it will not dismiss anything (medium or low) newer than 120 days and will only do 100 at each run
```
34 #this is the number of days a guest account has to accept before, they are considered to be deleted.
35 $riskolderthanindays = 120 #in days
36 #This is the levels you want to allowed to be cleared
37 $risklevel = @("low","medium") #low, medium, high
38 #this is a standard theshold, only the number provided below will be returned and deleted.
39 $removalthreshold = 100
```
* I recommend running this daily or weekly and increase the threshold.

## References
[Tutorial: Create a PowerShell Workflow runbook in Automation](https://docs.microsoft.com/en-us/azure/automation/learn/automation-tutorial-runbook-textual)
[Managed Identity with Azure Automation and Graph API](https://www.gericke.name/managed-identity-with-azure-automation-and-graph-api/#:~:text=%20Managed%20Identity%20with%20Azure%20Automation%20and%20Graph,Enterprise%20applications%20you...%205%20Reference.%20%20More%20)
