#Requires -modules Az.Accounts,Az.Resources 
#Requires -version 4.0
<#PSScriptInfo

.VERSION 2020.4.16

.GUID 476739f9-d907-4d5a-856e-71f9279955de

.AUTHOR Chad.Cox@microsoft.com
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

.DESCRIPTION 
 retrieves all objects and  

#> 
param($reportpath="$env:userprofile\Documents")
$report = "$reportpath\Azure_Resource_to_Account_Mapping_$(get-date -f yyyy-MM-dd-HH-mm).csv"


function resolveAzureRoleObject{
    [cmdletbinding()]
    param($name,$objecttype)
    if($objecttype -eq "User"){
        (get-azaduser -userprincipalname $name).id
    }
}

function expandAzureADGroup{
    [cmdletbinding()]
    param($objectid)
    Get-AzADGroupMember -GroupObjectId $objectid -PipelineVariable azgm | foreach{
        if($_.ObjectType -eq "Group"){
            expandAzureADGroup -objectid $_.id
        }else{
        $_ | select `
            @{Name="Signinname";Expression={$_.UserPrincipalName}}, `
            @{Name="DisplayName";Expression={$_.DisplayName}}, `
            @{Name="ObjectID";Expression={$_.ID}}, `
            ObjectType
        }
    }
}
function collectAzureSubscriptions{
    [cmdletbinding()]
    param()
    #Get-AzContext -ListAvailable | where {$_.Subscription}
    Get-AzSubscription
}
function Launcher{
    $availableazsubscriptions = collectAzureSubscriptions
    cls
    Write-host -ForegroundColor yellow "Select the Subscription you want to query:"
    $i = 0
    #$availableazsubscriptions | where {$_.Subscription} | foreach{
    $availableazsubscriptions | foreach{
        write-host "$i - $($_.name)"; $i++
    }
    write-host "$i - All of the Above"
    $option = read-host "Please enter a number 0 to $i..."
    if($option -eq $i){
        $availableazsubscriptions | foreach{
            write-host "Collecting roles for $($_.SubscriptionId)" -ForegroundColor Yellow
            collectAZRoles -subid $_.SubscriptionId
        }
    }else{
        write-host "Collecting roles for $($availableazsubscriptions[$option].name)" -ForegroundColor Yellow
        collectAZRoles -subid $availableazsubscriptions[$option].Subscription, -subname $availableazsubscriptions[$option].name
    }
}
function collectAZRoles{
    [cmdletbinding()]
    param($subid,$subname)
    write-host "Connecting to $subid" -ForegroundColor Yellow
    try{set-azcontext -Subscription $subid -ErrorAction Continue}
        catch{write-host "unable to connect to $subid" -ForegroundColor Red}
    write-host "Retrieving resources $($subid)" -ForegroundColor Yellow
    $azure_resources = get-azresource | group ResourceId -AsHashTable -AsString
    Get-AzRoleAssignment -IncludeClassicAdministrators -PipelineVariable azroas | foreach{
        foreach($azrole in $($azroas.RoleDefinitionName -split ";")){
            if($_.ObjectType -eq "Group"){
                expandAzureADGroup -objectid $azroas.ObjectID -PipelineVariable azadg | select `
                    @{Name="Group";Expression={$azroas.Displayname}}, `
                    @{Name="Scope";Expression={$azroas.scope}}, `
                    @{Name="RoleDefinitionName";Expression={$azrole}}, `
                    Displayname,signinname,objectid,ObjectType
            }else{
                $_ | select @{Name="Group";Expression={}}, `
                    @{Name="RoleDefinitionName";Expression={$azrole}}, `
                    Displayname,signinname,scope, `
                    @{Name="ObjectID";Expression={if($azroas.ObjectID){$azroas.ObjectID}else{resolveAzureRoleObject -name $azroas.SignInName -objecttype $azroas.objecttype}}}, `
                    ObjectType
            }
        }
    } | select @{N="Subscription";E={if(($_.scope -split "/")[1] -eq "subscriptions"){($_.scope -split "/")[2]}else{$subid}}}, `
        @{N="SubscriptionName";E={$subname}}, `
        @{N="ResourceGroup";E={if(($_.scope -split "/")[3] -eq "resourceGroups"){($_.scope -split "/")[4]}}}, `
        @{N="Provider";E={if(($_.scope -split "/")[5] -eq "providers"){($_.scope -split "/")[6]}}}, `
        @{N="Resource";E={if(($_.scope -split "/").count -gt 5){($_.scope -split "/")[-1]}}}, `
        scope,RoleDefinitionName, `
        group, ObjectID,ObjectType, Displayname, Signinname | export-csv $report -NoTypeInformation -Append
    write-host "Finished with $subid" -ForegroundColor Yellow
}

<#Function collectAzureRoles{
    [cmdletbinding()]
    param()
    #Collect Azure Resource Roles
           

    $file = "$working_directory\$($file_prefix)_t_azure_resources.tsv" 
    Get-AzContext -ListAvailable -PipelineVariable azco | set-azcontext | foreach{
        get-azresource | select `
        @{Name="subscriptionName";Expression={$azco.name}}, `
            @{Name="SubscriptionID";Expression={$azco.subscription}}, `
            @{Name="TenantId";Expression={$Azco.Tenant}}, `
            resourceid, resourcename, resourcetype, ResourceGroupName
    } 
    Get-AzContext -ListAvailable -PipelineVariable azco | set-azcontext | foreach{
        Get-AzRoleAssignment -IncludeClassicAdministrators -PipelineVariable azroas | foreach{
        foreach($azrole in $($azroas.RoleDefinitionName -split ";")){
            if($_.ObjectType -eq "Group"){
                expandAzureADGroup -objectid $azroas.ObjectID -PipelineVariable azadg | select `
                    @{Name="SubscriptionID";Expression={$azco.subscription}}, `
                    @{Name="TenantId";Expression={$Azco.Tenant}}, `
                    @{Name="ResourceID";Expression={$azroas.role}}, `
                    @{Name="RoleDefinitionID";Expression={$azroas.RoleDefinitionID}}, `
                    @{Name="RoleDefinitionName";Expression={$azrole}}, `
                    @{Name="Group";Expression={$azroas.Displayname}}, `
                    Displayname,signinname,objectid,ObjectType
            }else{        
                $_ | select `
                    @{Name="SubscriptionID";Expression={$azco.subscription}}, `
                    @{Name="TenantId";Expression={$Azco.Tenant}}, `
                    @{Name="ResourceID";Expression={$_.role}}, `
                    RoleDefinitionID, `
                    @{Name="RoleDefinitionName";Expression={$azrole}}, `
                    @{Name="Group";Expression={}}, `
                    Displayname,signinname,
                    @{Name="ObjectID";Expression={if($azroas.ObjectID){$azroas.ObjectID}else{resolveAzureRoleObject -name $azroas.SignInName -objecttype $azroas.objecttype}}}, `
                    ObjectType
                }
            }
        }
    }
}#>

connect-azaccount
Launcher
write-host "Results can be found here $report"
