#login
login-MSGraph
#export all enabled conditional access policies
$uri = "$script:graphendpoint/beta/identity/conditionalAccess/policies"

$all_capolicies = get-MSGraphRequest -uri $uri
$totalUsers = Get-MgBetaUserCount -ConsistencyLevel "Eventual" -filter "AccountEnabled eq true"
$totalGuest = Get-MgBetaUserCount -ConsistencyLevel "Eventual" -filter "userType eq 'Guest'"

$all_capolicies | foreach {$cap="";$cap=$_
    $IncludedUsers = 0
    if($cap.conditions.users.includeUsers -contains "All"){
        $IncludedUsers = $totalUsers
    }else{
        $IncludedUsers = ($cap.conditions.users.includeUsers).count
    }
    if(($cap.conditions.users.includeGroups | measure).count -gt 0){
        $cap.conditions.users.includeGroups | foreach{
         $IncludedUsers += Get-MgBetaGroupTransitiveMemberCount -GroupId $_ -ConsistencyLevel "Eventual"
        }
    }
    if(($cap.conditions.users.includeRoles | measure).count -gt 0){
        $cap.conditions.users.includeRoles | foreach{
           $IncludedUsers +=  (Get-MgBetaRoleManagementDirectoryRoleDefinition -filter "TemplateId eq '$($_)'" | select * | foreach{
                Get-MgBetaRoleManagementDirectoryRoleAssignment -filter "RoleDefinitionId eq '$($_.id)'"
            } | select PrincipalId -Unique).count
        }
    }
    if(($cap.conditions.users.includeGuestsOrExternalUsers | measure).count -gt 0){
        $IncludedUsers += $totalGuest
    }
        $ExcludedUsers = 0
    if($cap.conditions.users.excludeUsers -contains "All"){
        $ExcludedUsers = $totalUsers
    }else{
        $ExcludedUsers = ($cap.conditions.users.excludeUsers).count
    }
    if(($cap.conditions.users.excludeGroups | measure).count -gt 0){
        $cap.conditions.users.excludeGroups | foreach{
         $ExcludedUsers += Get-MgBetaGroupTransitiveMemberCount -GroupId $_ -ConsistencyLevel "Eventual"
        }
    }
    if(($cap.conditions.users.excludeRoles | measure).count -gt 0){
        $cap.conditions.users.excludeRoles | foreach{
           $ExcludedUsers +=  (Get-MgBetaRoleManagementDirectoryRoleDefinition -filter "TemplateId eq '$($_)'" | select * | foreach{
                Get-MgBetaRoleManagementDirectoryRoleAssignment -filter "RoleDefinitionId eq '$($_.id)'"
            } | select PrincipalId -Unique).count
        }
    }
    if(($cap.conditions.users.excludeGuestsOrExternalUsers | measure).count -gt 0){
        $ExcludedUsers += $totalGuest
    }
    $cap | select @{n='ConditionalAccessPolicyName';e={$_.displayName}},state, @{n='TargetedUserCount';e={$IncludedUsers}},@{n='ExcludedUserCount';e={$ExcludedUsers}}
    
} | export-csv .\usercountscopedforeachconditionalaccesspolicy.csv -NoTypeInformation
