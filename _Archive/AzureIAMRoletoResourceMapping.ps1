#Requires -modules azureadpreview,Az.Resources,Az.Accounts
#Requires -version 4.0
<#PSScriptInfo

.VERSION 2020.11.20

.GUID ad019fa9-f114-4c1a-8079-c2d10d2c6527

.AUTHOR Chad Cox

.COMPANYNAME Microsoft

.DESCRIPTION 
 Export all azure subscription, resources and management groups along with all the PIM and Role assignments.

Need to add Get-AzUserAssignedIdentity
https://docs.microsoft.com/en-us/powershell/module/az.managedserviceidentity/get-azuserassignedidentity?view=azps-4.3.0
Get-AzKeyVault
https://docs.microsoft.com/en-us/powershell/module/az.keyvault/get-azkeyvault?view=azps-4.3.0
Get-AzApplicationGateway
Also AKS is still a blackhole around ID's

research
https://github.com/JulianHayward/Azure-MG-Sub-Governance-Reporting/blob/master/pwsh/AzGovViz.ps1
https://github.com/rodrigosantosms/azure-subscription-migration/blob/master/export-RBAC.ps1
#>
param($scriptpath="c:\temp")
if(!(test-path $scriptpath)){
    new-item -Path $scriptpath -ItemType Directory
}

connect-azaccount
connect-azuread

cd $scriptpath

#when enumerating large environments this also enumerates all the visual studio subs.  
#the goal of this is to make sure to return the script back to the default sub for later
$default_sub = Get-AzContext

#region Supporting Functions
function enumerate-aadgroup{
    param($objectid)
    get-azureadgroupmember -ObjectId $objectid -pv mem | foreach{
        $_ | select @{Name="ObjectID";Expression={$mem.objectId}}, `
            @{Name="ObjectType";Expression={"GroupMember - $($mem.ObjectType)"}}, `
            @{Name="Displayname";Expression={$mem.DisplayName}}, `
            @{Name="SigninName";Expression={$mem.userprincipalname}}
        if($_.group){
            enumerate-aadgroup -ObjectId $_.objectid
        }
    }
}
function check-file{
    param($file)
    if(!(Test-Path $file)){
        write-host "$file not found"
        return $true      
    }elseif(!((Get-Item $file).length/1KB -gt 1/1kb)){
        write-host "$file is empty"
        return $true
    }elseif((get-item -Path $file).LastWriteTime -lt (get-date).AddDays(-3)){
        write-host "$file is older than 3 days"
        return $true
    }else{
        write-host "$file seems reusable"
        return $false
    }
}
function getallmg{
    [cmdletbinding()]
    param($mgn)
    write-information "Expanding Management Group $mgn"
    Get-AzManagementGroup -GroupName $mgn -expand -pv amg | select -ExpandProperty children | foreach{
        $_ | select @{Name="ID";Expression={$amg.id}}, `
            @{Name="name";Expression={$amg.displayname}}, `
            @{Name="type";Expression={$amg.type}}, `
            @{Name="ChildID";Expression={$_.id}}, `
            @{Name="ChildType";Expression={$_.type}}, `
            @{Name="Childname";Expression={$_.displayname}}
            if($_.type -eq "/providers/Microsoft.Management/managementGroups"){
                getallmg -mgn $_.name
            }
    }  
}
function expandallmg{
    param($mg)
    if($hashallmg.ContainsKey($mg)){
    $hashallmg[$mg] | foreach{ $_ | select `
        @{Name="ID";Expression={$_.id}}, `
        @{Name="name";Expression={$_.name}}, `
        @{Name="type";Expression={$_.type}},
        @{Name="ChildID";Expression={$omg.Childid}}, `
        @{Name="ChildType";Expression={$omg.childtype}}, `
        @{Name="Childname";Expression={$omg.childname}}
        expandallmg -mg $_.ID}
    }
}
#endregion
#region Management Groups Exports
$mg_File = ".\mg.tmp"
if(check-file -file $mg_file){
    write-host "Exporting Azure Management Group Relationships"
    $allmg = getallmg -mgn (Get-AzureADTenantDetail).objectid 
    $hashallmg = $allmg | group ChildID -AsHashTable -AsString

    @(foreach($omg in $allmg){
        expandallmg -mg $omg.ChildID
    }) | export-csv $mg_File -NoTypeInformation
}

$res_file = ".\res.tmp"
if(check-file -file $res_file){
    write-host "Exporting Azure Management Groups"    
    get-azManagementGroup | select `
        @{Name="ParentID";Expression={$_.id}}, `
        @{Name="ParentName";Expression={$_.displayname}}, `
        @{Name="ParentType";Expression={$_.type}}, `
        @{Name="ResourceID";Expression={$_.ID}}, `
        @{Name="ResourceName";Expression={$_.displayname}}, `
        @{Name="ResourceType";Expression={$_.type}}, `
        ResourceGroupName,ResourceGroupID | export-csv $res_file -NoTypeInformation

    Write-host "Exporting All Azure Subscriptions and Resources"
    get-azsubscription -pv azs | where {$_.state -eq "Enabled"} | Set-AzContext | foreach{
        $azs | select @{Name="ParentID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ParentName";Expression={"$($azs.name)"}}, `
            @{Name="ParentType";Expression={"/subscriptions"}}, `
            @{Name="ResourceID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ResourceName";Expression={"$($azs.name)"}}, `
            @{Name="ResourceType";Expression={"/subscriptions"}}, `
            @{Name="ResourceGroupName";Expression={}}, `
            @{Name="ResourceGroupID";Expression={}}
        get-azResource -pv azr | select @{Name="ParentID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ParentName";Expression={"$($azs.name)"}}, `
            @{Name="ParentType";Expression={"/subscriptions"}}, `
            @{Name="ResourceID";Expression={$azr.resourceid}}, `
            @{Name="ResourceName";Expression={$azr.name}}, `
            @{Name="ResourceType";Expression={$azr.ResourceType}}, `
            @{Name="ResourceGroupName";Expression={$azr.ResourceGroupName}}, `
            @{Name="ResourceGroupID";Expression={if($azr.ResourceGroupName){($azr.resourceid -split "/")[0..4] -join "/"}}}
         get-azResourceGroup -pv azrg | select @{Name="ParentID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ParentName";Expression={"$($azs.name)"}}, `
            @{Name="ParentType";Expression={"/subscriptions"}}, `
            @{Name="ResourceID";Expression={$azrg.resourceid}}, `
            @{Name="ResourceName";Expression={$azrg.ResourceGroupName}}, `
            @{Name="ResourceType";Expression={"/resourceGroups"}}, `
            @{Name="ResourceGroupName";Expression={$azrg.ResourceGroupName}}, `
            @{Name="ResourceGroupID";Expression={$azrg.ResourceID}}
    } | export-csv $res_file -NoTypeInformation -Append
}
#endregion
#region Role Export
$rbac_file = ".\rbac.tmp"
if(check-file -file $rbac_file){
    write-host "Exporting all Azure Role Assignment from Subscriptions"
    import-csv $mg_File | where {$_.childtype -eq "/providers/Microsoft.Management/managementGroups"} | select -expandproperty childid -unique -pv mg | foreach{
        get-azRoleAssignment -scope $mg -pv azr | where {$_.scope -eq $mg} | select scope, RoleDefinitionName,RoleDefinitionId,ObjectId,ObjectType, `
            DisplayName,SignInName,AssignmentState, @{Name="AssignmentType";Expression={"azRoleAssignment"}}
    } | export-csv $rbac_file -NoTypeInformation
    get-azsubscription -pv azs | where {$_.state -eq "Enabled"} | Set-AzContext | foreach{
        get-azRoleAssignment -pv azr | select scope, RoleDefinitionName,RoleDefinitionId,ObjectId,ObjectType, `
            DisplayName,SignInName,AssignmentState, @{Name="AssignmentType";Expression={"azRoleAssignment"}}
    } | select * -unique | export-csv $rbac_file -NoTypeInformation -Append
}

$pim_File = ".\pim.tmp"
if(check-file -file $pim_File){
    write-host "Exporting all Privileged Identity Management Enabled Azure Roles and Members"
    import-csv $rbac_file | group scope -pv azr  | foreach{
        Get-AzureADMSPrivilegedResource -ProviderId AzureResources -filter "externalId eq '$(($azr).name)'" -pv pim | foreach{
            Get-AzureADMSPrivilegedRoleAssignment -ProviderId AzureResources -ResourceId $pim.ID -pv azpra | where MemberType -eq "Direct" | foreach{
                $role = Get-AzureADMSPrivilegedRoleDefinition -ProviderId AzureResources -id $azpra.RoleDefinitionId -ResourceId $azpra.ResourceId
                    Get-AzureADObjectByObjectId -ObjectId $azpra.SubjectId -pv member | select `
                         @{Name="Scope";Expression={$(($azr).name)}}, `
                         @{Name="RoleDefinitionName";Expression={$role.DisplayName}}, `
                         @{Name="RoleDefinitionId";Expression={$azpra.RoleDefinitionId}}, `
                         @{Name="ObjectID";Expression={$azpra.SubjectId}}, `
                         @{Name="ObjectType";Expression={$member.ObjectType}}, `
                         @{Name="Displayname";Expression={$member.DisplayName}}, `
                         @{Name="SigninName";Expression={$member.userprincipalname}}, `
                         @{Name="AssignmentState";Expression={if($azpra.AssignmentState -like "Active" -and $azpra.EndDateTime -eq $null) `
                          {"$($azpra.AssignmentState) - Permanent"}elseif($azpra.AssignmentState -like "Active" -and $azpra.EndDateTime -like "*") `
                          {"$($azpra.AssignmentState) - Elevated"}else{$azpra.AssignmentState}}}, `
                         @{Name="AssignmentType";Expression={"PrivilegedRoleAssignment"}}
            }
        }
    } | export-csv $pim_File -notypeinformation
}
#endregion
#region Formatting and Creating Final Report

Set-AzContext -Subscription $default_sub.Subscription

$hash_inherited = import-csv .\rbac.tmp | select scope | group scope -AsHashTable -AsString


write-host "Creating Azure Resource Lookup Hash Table"
$hash_res = import-csv $res_file | group ParentID -AsHashTable -AsString

write-host "Creating Hash Lookup Table for PIM Enabled Resources"
$hash_pimenabled = import-csv $rbac_file -pv azr | where Displayname -eq "MS-PIM" | group scope -AsHashTable -AsString

$resm_File = ".\AzureResourceRelationships.csv"
Write-host "Mapping All Management Groups to themselves for scopeid reference"
$allmg | where childtype -eq "/providers/Microsoft.Management/managementGroups" | select @{N="UniqueID";E={([guid]::newguid()).guid}}, `
    @{Name="ScopeID";Expression={$_.childid}},@{Name="ScopeName";Expression={$_.childname}}, `
    @{Name="ScopeType";Expression={$_.childtype}},@{Name="ResourceID";Expression={$_.childid}},@{Name="ResourceName";Expression={$_.childname}}, `
    @{Name="ResourceType";Expression={$_.childtype}},ResourceGroup, `
    @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.childid)}}, `
    @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.childid)}}, `
    @{Name="Subscription";Expression={}} | export-csv $resm_File -notypeinformation -Append
Write-host "Mapping All Management Groups to child management groups for scopeid reference"
import-csv $mg_File -pv mg | select @{N="UniqueID";E={([guid]::newguid()).guid}},@{Name="ScopeID";Expression={$mg.ID}},@{Name="ScopeName";Expression={$mg.name}}, `
        @{Name="ScopeType";Expression={$mg.Type}},@{Name="ResourceID";Expression={$mg.childid}},@{Name="ResourceName";Expression={$mg.childname}}, `
        @{Name="ResourceType";Expression={$mg.childtype}},ResourceGroup, `
        @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($mg.ID)}}, `
        @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.ID)}}, `
        @{Name="Subscription";Expression={}} | export-csv $resm_File -notypeinformation -Append
Write-host "Mapping All Management Groups to Resources based on subscriptions"
import-csv $mg_File -pv mg | foreach{
    $hash_res[$mg.childid] | select @{N="UniqueID";E={([guid]::newguid()).guid}},@{Name="ScopeID";Expression={$mg.ID}},@{Name="ScopeName";Expression={$mg.name}}, `
        @{Name="ScopeType";Expression={$mg.Type}},ResourceID,ResourceName,ResourceType,@{Name="ResourceGroup";Expression={$_.ResourceGroupName}}, `
        @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($mg.ID)}}, `
        @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.ResourceID)}}, `
        @{Name="Subscription";Expression={$_.Subscription}}
} | export-csv $resm_File -notypeinformation -Append
Write-host "Adding Resource Reference to Resource"
import-csv $res_file -pv mg | select @{N="UniqueID";E={([guid]::newguid()).guid}},@{Name="ScopeID";Expression={$_.ResourceID}},@{Name="ScopeName";Expression={$_.ResourceName}}, `
    @{Name="ScopeType";Expression={$_.ResourceType}},ResourceID,ResourceName,ResourceType,@{Name="ResourceGroup";Expression={$mg.ResourceGroupName}}, `
    @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.resourceid)}}, `
        @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.ResourceID)}}, `
        @{Name="Subscription";Expression={$mg.subscription}} | export-csv $resm_File -Append
write-host "Adding Subscription references to resource"
import-csv $res_file -pv mg | select @{N="UniqueID";E={([guid]::newguid()).guid}},@{Name="ScopeID";Expression={$_.ParentID}},@{Name="ScopeName";Expression={$_.ParentName}}, `
    @{Name="ScopeType";Expression={$_.ParentType}},ResourceID,ResourceName,ResourceType,@{Name="ResourceGroup";Expression={$mg.ResourceGroupName}}, `
    @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.parentid)}}, `
        @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.ResourceID)}}, `
        @{Name="Subscription";Expression={$mg.subscription}} | export-csv $resm_File -Append
write-host "Adding Resource group references to resources"
import-csv $res_file -pv mg | where {($_.ResourceGroupName)} | select @{N="UniqueID";E={([guid]::newguid()).guid}},@{Name="ScopeID";Expression={$_.ResourceGroupID}},@{Name="ScopeName";Expression={$_.ResourceGroupName}}, `
    @{Name="ScopeType";Expression={"/resourceGroups"}},ResourceID,ResourceName,ResourceType,@{Name="ResourceGroup";Expression={$mg.ResourceGroupName}}, `
    @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.ResourceGroupID)}}, `
        @{Name="Direct";Expression={$hash_inherited.ContainsKey($_.ResourceID)}}, `
        @{Name="Subscription";Expression={$mg.subscription}} | export-csv $resm_File -Append

write-host "Flushing Azure Resource Lookup Hash Table"
$hash_res = @{}

$grpm_File = ".\grpm.tmp"
if(check-file -file $grpm_File){
    write-host "Expanding Azure AD Groups being used in Azure Roles"
    @(import-csv $rbac_file; import-csv $pim_File) | where ObjectType -eq "group" -PipelineVariable grp | foreach{
        enumerate-aadgroup -objectid $_.objectid | select @{Name="Scope";Expression={$grp.scope}}, `
            @{Name="RoleDefinitionName";Expression={$grp.RoleDefinitionName}}, `
            @{Name="RoleDefinitionId";Expression={$grp.RoleDefinitionId}}, `
            ObjectId,ObjectType,DisplayName,SignInName, `
            @{Name="AssignmentState";Expression={$grp.AssignmentState}}, `
            @{Name="AssignmentType";Expression={$grp.AssignmentType}} 
    } | sort scope,objectid | select * -Unique | export-csv $grpm_File -NoTypeInformation
}
$role_File = ".\AzureRoleAssignment.csv"
@(import-csv $rbac_file; import-csv $pim_File; import-csv $grpm_File) | export-csv $role_File -NoTypeInformation
