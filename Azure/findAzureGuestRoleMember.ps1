#
.VERSION 2021.2.18
.GUID 809ca830-a28a-45ea-888f-aa200e857d98
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
#> 

$hash_sublookup = Get-AzSubscription | select name, id | group id -AsHashTable -AsString

Get-AzSubscription | set-azcontext | foreach{
    Get-AzRoleAssignment -IncludeClassicAdministrators -pv assignment | foreach{
        foreach($rn in ($assignment.RoleDefinitionName -split ";")){
            if($assignment.ObjectType -eq "Group"){#enumerate members of group, this is not recursive
                Get-AzADGroupMember -GroupObjectId $assignment.objectid -pv gm | select `
                    @{Name="Scope";Expression={$assignment.Scope}}, `
                @{Name="ScopeType";Expression={($assignment.Scope -split "/")[-2]}}, `
                @{Name="RoleDefinitionName";Expression={$rn}}, `
                @{Name="RoleDefinitionId";Expression={$assignment.RoleDefinitionId}}, `
                @{Name="DisplayName";Expression={$gm.DisplayName}}, `
                @{Name="SignInName";Expression={$gm.UserPrincipalName}}, `
                @{Name="ObjectID";Expression={$gm.ID}}, `
                @{Name="ObjectType";Expression={"MemberOf - $($assignment.DisplayName)"}}, `
                @{Name="Subscription";Expression={if(!(($assignment.Scope -split "/")[-2] -eq "")){`
                    "$($hash_sublookup[($assignment.Scope -split "/")[2]].name) ($($hash_sublookup[($assignment.Scope -split "/")[2]].id))"}}}
            
            }#enumerate all the accounts
            $_ | select @{Name="Scope";Expression={$assignment.Scope}}, `
                @{Name="ScopeType";Expression={($assignment.Scope -split "/")[-2]}}, `
                @{Name="RoleDefinitionName";Expression={$rn}}, `
                @{Name="RoleDefinitionId";Expression={$assignment.RoleDefinitionId}}, `
                @{Name="DisplayName";Expression={$assignment.DisplayName}}, `
                @{Name="SignInName";Expression={$assignment.SignInName}}, `
                @{Name="ObjectID";Expression={$assignment.ObjectID}}, `
                @{Name="ObjectType";Expression={$assignment.Objecttype}}, `
                @{Name="Subscription";Expression={if(!(($assignment.Scope -split "/")[-2] -eq "managementGroups")){`
                    "$($hash_sublookup[($assignment.Scope -split "/")[2]].name) ($($hash_sublookup[($assignment.Scope -split "/")[2]].id))"}}}
        }
    } | where {$_.SignInName -like "*#EXT#*"}
} | export-csv .\azureGuestRoleMembers.csv -notypeinformation
