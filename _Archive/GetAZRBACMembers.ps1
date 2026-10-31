<#
.VERSION 2023.4.27
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


function gatherAzureRoleMembers{
     [cmdletbinding()]
    param($asub)
    Get-AzRoleAssignment -IncludeClassicAdministrators -pv assignment | foreach{
        $assignment.RoleDefinitionName -split ";" | foreach{$rn=$null;$rn=$_
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

    
    Get-AzRoleEligibilitySchedule -Scope $asub | foreach{$assignment = $null;$assignment = $_
           $assignment  | select `
                @{Name="Scope";Expression={$assignment.scope}}, `
                @{Name="ScopeType";Expression={$assignment.type}}, `
                @{Name="RoleDefinitionName";Expression={$assignment.RoleDefinitionDisplayName}}, `
                @{Name="RoleDefinitionId";Expression={($assignment.RoleDefinitionId -split "/")[-1]}}, `
                @{Name="DisplayName";Expression={$assignment.PrincipalDisplayName}}, `
                @{Name="SignInName";Expression={$assignment.PrincipalEmail}}, `
                @{Name="ObjectID";Expression={$assignment.PrincipalId}}, `
                @{Name="ObjectType";Expression={$assignment.PrincipalType}}, `
                @{Name="Subscription";Expression={$asub}}, `
                @{Name="AssignmentState";Expression={"Eligible"}}, `
                @{Name="Source";Expression={"Azure PIM"}}
    }
}

Get-AzSubscription -pv sub | where {$_.state -eq 'Enabled' -and !($_.name -like "*Visual Studio*")} | set-azcontext | foreach{
    gatherAzureRoleMembers -asub "/subscriptions/$($sub.id)"
} | export-csv ".\AzureRoleAssignmentsReport.csv" -NoTypeInformation
