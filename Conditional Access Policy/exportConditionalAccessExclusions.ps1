<#PSScriptInfo
.VERSION 2022.10.7
.GUID e7a48d24-7c7a-4b21-b32d-2a86c844b90a
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
.TAGS 
.DETAILS
.EXAMPLE
#>
param($defaultpath="$env:USERPROFILE\downloads")
cd $defaultpath

Connect-MgGraph -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.ReadWrite.All", "Directory.AccessAsUser.All"
Select-MgProfile -Name beta

function expandGroupMembership{
    [cmdletbinding()]
    param($id)
    if(!($script:alreadyenumerated.containskey($id))){
        Get-MgGroupMember -GroupId $id | select id -ExpandProperty AdditionalProperties | convertto-json | convertfrom-json | foreach{
            $_ | select @{N="CAP";E={$cap.displayname}},id, displayName, userPrincipalName
            if($_."@odata.type" -eq "#microsoft.graph.group"){
                if(!($script:alreadyenumerated.containskey($_.id))){
                    $script:alreadyenumerated.add($_.id,$true)
                    write-host "found group"
                    expandGroupMembership -groupid $_.id
                }

            }
        }
    }
}

function getcapexclusions{
    [cmdletbinding()]
    param()
    Get-MgIdentityConditionalAccessPolicy | where {$_.state -eq "enabled"} | foreach{$cap=$null;$cap=$_
        $script:alreadyenumerated = @{}
        $cap.conditions.users.excludeUsers | foreach{
            if($_ -ne "GuestsOrExternalUsers"){
                try{Get-MgUser -userid $_ | select @{N="CAP";E={$cap.displayname}},id, displayName, userPrincipalName}
                    catch{$_ | select @{N="CAP";E={$cap.displayname}},@{N="id";E={$_}}, @{N="displayName";E={"not resolving"}}, userPrincipalName}
            }else{
                $_ | select @{N="CAP";E={$cap.displayname}},@{N="id";E={$_}}, displayName, userPrincipalName
            }
        }
        $cap.conditions.users.excludeGroups | foreach{
            $script:alreadyenumerated = @{}
            get-mggroup -GroupId $_ | select @{N="CAP";E={$cap.displayname}},id, displayName, userPrincipalName
            expandGroupMembership -id $_
        }
        $cap.conditions.users.excludeRoles | foreach{$role = $null; $role=$_
            Get-MgDirectoryRole -All | where {$_.RoleTemplateId -eq $role} | foreach{
                $_ | select @{N="CAP";E={$cap.displayname}},id, displayName, userPrincipalName
                Get-MgDirectoryRoleMember -DirectoryRoleId $_.id -all | select id | foreach{
                    if(!($script:alreadyenumerated.containskey($_.id))){
                        $script:alreadyenumerated.add($_.id,$true)
                        $rolemem=$null;$rolemem=Get-MgDirectoryObject -DirectoryObjectId $_.id | `
                            select id -ExpandProperty AdditionalProperties | convertto-json -depth 99 | convertfrom-json
                        $rolemem | select @{N="CAP";E={$cap.displayname}},id, displayName, userPrincipalName
                        if($rolemem."@odata.type" -eq "#microsoft.graph.group"){   
                            expandGroupMembership -id $rolemem.id
                        }
                    }
                }
            }
        }
    }
}

getcapexclusions | select cap, id, displayName, userPrincipalName -Unique | export-csv .\conditional_access_policy_user_exclusions.csv -notypeinformation
