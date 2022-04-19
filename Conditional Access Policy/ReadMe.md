# Conditional Access Policy Scripts
## Add-ExclusionGroupALLCAP.ps1
* this script creates a group
* adds the group to a admin unit
* assigns the group to a conditional access policy
* This will be performed against each policy

## Import-AADRecommendedConditionalAccessPolicies.ps1
* This script imports recommended policies outlined in this link [Click Here](https://github.com/chadmcox/Azure_Active_Directory/wiki/Azure-AD-Conditional-Access-Policies)
* Each imported conditional access policy will start with read only and will be in report only

## add-BreakGlasstoConditionalAccessPolicyExclusion.ps1
* This script will add a breakglass to every conditional access policy it is not excluded in
* can be ran several times to add multiple accounts
