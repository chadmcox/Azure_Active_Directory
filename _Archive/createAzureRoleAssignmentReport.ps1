<#
.VERSION 2023.2.22
.GUID 18c37c40-e24d-4524-8b78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
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

.DESCRIPTION
this will dump all rbac and pim members from all subscriptions
use the switch to expand group membership

this is going to create two tmp files, the first one is all the azure iam role members.
if this exist and greater than 1kb and not older than 3 days then the script will skip
building a new copy of that file and will use that file to start the pim scan.
the pim scan happens no matter what.

Once both are complete it combines both tmp files to one file

#> 

param([switch]$expandgroupmember,$defaultpath=".\")
connect-azaccount

cd $defaultpath

$startTime = get-date

function check-file{
    param($file)
    if(!(Test-Path $file)){
        write-host "$file not found"
        return $true      
    }elseif(!((Get-Item $file).length/1KB -gt 1/1kb)){
        write-host "$file is empty"
        return $true
    }elseif((get-item $file).LastWriteTime -lt (get-date).AddDays(-3)){
        write-host "$file is older than 3 days"
        return $true
    }else{
        write-host "$file seems reusable"
        return $false
    }
}


function findScopeCaseforPIM{
    [cmdletbinding()]
    param($scope)
    if(($scope -split "/")[-2] -eq "managementGroups"){
        try{return (Get-AzManagementGroup -GroupName ($Scope -split "/")[-1]).id}catch{return $scope}
    }elseif(($scope -split "/")[-2] -eq "subscriptions"){
        try{return "/subscriptions/$((Get-AzSubscription -SubscriptionId ($Scope -split "/")[-1]).id)"}catch{return $scope}
    }elseif(($scope -split "/")[-2] -eq "resourceGroups"){
        try{return (Get-AzResourceGroup -id $scope).ResourceId}catch{return $scope}
    }elseif($scope -eq "/"){
        return $scope
    }else{
        try{return (Get-AzResource -ResourceId $scope).ResourceId}catch{return $scope}
    }
}
function gatherAzureRoleMembers{
    [cmdletbinding()]
    param()
    $sub_count = (Get-AzSubscription).count
    $i = 0
    #condider putting in the following where clause after Get-AzSubscription -pv sub
    #where {($_.state -eq "Enabled") -and (!($_.name -like "*Visual Studio*") -and !($_.name -like "*Free Trial*") -and !($_.name -like "*Azure for Students*"))}

    Get-AzSubscription -pv sub | set-azcontext | foreach{$i++
        write-host "Step 1 of 2 / Sub $i of $sub_count - Exporting Roles from: $($sub.name)"
        Get-AzRoleAssignment -IncludeClassicAdministrators -pv assignment | foreach{
            foreach($rn in ($assignment.RoleDefinitionName -split ";")){
                #if the object is a group and the switch is enabled then it will enumerate the groups
                if($assignment.ObjectType -eq "Group" -and $expandgroupmember -eq $true){#enumerate members of group, this is not recursive
                    Get-AzADGroupMember -GroupObjectId $assignment.objectid -pv gm | select `
                        @{Name="Scope";Expression={$assignment.Scope}}, `
                        @{Name="ScopeType";Expression={($assignment.Scope -split "/")[-2]}}, `
                        @{Name="RoleDefinitionName";Expression={$rn}}, `
                        @{Name="RoleDefinitionId";Expression={$assignment.RoleDefinitionId}}, `
                        @{Name="DisplayName";Expression={$gm.DisplayName}}, `
                        @{Name="SignInName";Expression={$gm.UserPrincipalName}}, `
                        @{Name="ObjectID";Expression={$gm.ID}}, `
                        @{Name="ObjectType";Expression={"MemberOf - $($assignment.DisplayName)"}}, `
                        @{Name="Subscription";Expression={"$($sub.name) ($($sub.id))"}}, `
                        AssignmentState,@{Name="Source";Expression={"Azure IAM"}}
            
                }#enumerate all the accounts
                $_ | select @{Name="Scope";Expression={$assignment.Scope}}, `
                    @{Name="ScopeType";Expression={($assignment.Scope -split "/")[-2]}}, `
                    @{Name="RoleDefinitionName";Expression={$rn}}, `
                    @{Name="RoleDefinitionId";Expression={$assignment.RoleDefinitionId}}, `
                    @{Name="DisplayName";Expression={$assignment.DisplayName}}, `
                    @{Name="SignInName";Expression={$assignment.SignInName}}, `
                    @{Name="ObjectID";Expression={$assignment.ObjectID}}, `
                    @{Name="ObjectType";Expression={$assignment.Objecttype}}, `
                    @{Name="Subscription";Expression={"$($sub.name) ($($sub.id))"}}, `
                    AssignmentState,  @{Name="Source";Expression={"Azure IAM"}}
            }
        } 
    } 
}

function gatherPIMRoleMembers{
    $hash_scopes = import-csv $azure_rbac_file | select scope, Subscription -unique | group scope -AsHashTable -AsString
    #$uniqueScopes = import-csv $azure_rbac_file | where DisplayName -eq "MS-PIM" | select scope -Unique
    $pim_count = $hash_scopes.count
    $i=0
    foreach($sc in $hash_scopes.keys){$i++
        write-host "Step 2 of 2 / Scope $i of $pim_count - Exporting PIM Roles from: $sc)"
        Get-AzRoleEligibilitySchedule -Scope $sc  | where {$_.membertype -ne "Inherited"} | foreach{$assignment = $null;$assignment = $_
            write-host "Enumerating PIM: $($assignment.RoleDefinitionDisplayName)"
                    
            $hash_scopes[$sc].Subscription | foreach{$sub = $null; $sub = $_
            if($assignment.PrincipalType -eq "Group" -and $expandgroupmember -eq $true){
                Get-AzADGroupMember -GroupObjectId $assignment.PrincipalId -pv gm | select `
                    @{Name="Scope";Expression={$sc}}, `
                    @{Name="ScopeType";Expression={($sc -split "/")[-2]}}, `
                    @{Name="RoleDefinitionName";Expression={$assignment.RoleDefinitionDisplayName}}, `
                    @{Name="RoleDefinitionId";Expression={($assignment.RoleDefinitionId -split "/")[-1]}}, `
                    @{Name="DisplayName";Expression={$gm.DisplayName}}, `
                    @{Name="SignInName";Expression={$gm.UserPrincipalName}}, `
                    @{Name="ObjectID";Expression={$gm.ID}}, `
                    @{Name="ObjectType";Expression={"MemberOf - $($assignment.PrincipalDisplayName)"}}, `
                    @{Name="Subscription";Expression={$sub}}, `
                    @{Name="AssignmentState";Expression={"Eligible"}}, `
                    @{Name="Source";Expression={"Azure PIM"}}
            } 
                $assignment | select `
                    @{Name="Scope";Expression={$sc}}, `
                    @{Name="ScopeType";Expression={($sc -split "/")[-2]}}, `
                    @{Name="RoleDefinitionName";Expression={$assignment.RoleDefinitionDisplayName}}, `
                    @{Name="RoleDefinitionId";Expression={($assignment.RoleDefinitionId -split "/")[-1]}}, `
                    @{Name="DisplayName";Expression={$assignment.PrincipalDisplayName}}, `
                    @{Name="SignInName";Expression={$assignment.PrincipalEmail}}, `
                    @{Name="ObjectID";Expression={$assignment.PrincipalId}}, `
                    @{Name="ObjectType";Expression={$assignment.PrincipalType}}, `
                    @{Name="Subscription";Expression={$sub}}, `
                    @{Name="AssignmentState";Expression={"Eligible"}}, `
                    @{Name="Source";Expression={"Azure PIM"}}
            }
                    
            
        }
    }
}
$azure_rbac_file = ".\azureRoleMembers.tmp"
if(check-file -file $azure_rbac_file){
    write-host "Getting all Azure Roles"
    gatherAzureRoleMembers | export-csv $azure_rbac_file -notypeinformation
}


$azure_pimrole_file = ".\azurePimRoleMembers.tmp"
write-host "Getting all Azure Roles in PIM"
gatherPIMRoleMembers | export-csv $azure_pimrole_file -NoTypeInformation

@(import-csv $azure_rbac_file; import-csv $azure_pimrole_file) | export-csv ".\AzureRoleAssignmentsReport.csv" -NoTypeInformation
write-host "Completed after $("{0:N2}" -f (New-TimeSpan -start $startTime -end (get-date)).TotalHours) hours"
write-host "Results found in AzureRoleAssignmentsReport.csv"
