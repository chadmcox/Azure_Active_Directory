Connect-MgGraph
Select-MgProfile -Name "beta"
Import-Module Microsoft.Graph.Identity.Governance

$context = get-mgcontext

function retrieveaadrolemembers{
    [cmdletbinding()] 
    param()
    Get-MgPrivilegedAccessRoleDefinition -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | foreach{
        $role = $null; $role = $_
        write-host "Exporting $($role.DisplayName) $($role.id)"
        Get-MgPrivilegedAccessRoleAssignment -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)' and roleDefinitionId eq '$($role.id)'" | `
            select @{N="roleId";E={$role.Id}}, @{N="roleName";E={$role.DisplayName}}, SubjectId, AssignmentState, `
                @{N="Permanant";E={if($_.AssignmentState -eq "Active" -and $_.EndDateTime -eq $null){$true}else{$false}}}
    }
}
function retrieveactualobject{
    [cmdletbinding()] 
    param($objectid,$members)
    Get-MgDirectoryObject -DirectoryObjectId $objectid | select -ExpandProperty AdditionalProperties | Convertto-Json | ConvertFrom-Json | select `
        "@odata.type", displayName, @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, `
            @{N="SubjectId";E={$objectid}}, @{N="AssignmentState";E={$members.AssignmentState}}, `
            @{N="IsMfaRegistered";E={(Get-MgReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId $objectid).IsMfaRegistered}}, `
            @{N="Permanant";E={$members.Permanant}}
}
function expandgroup{
    [cmdletbinding()] 
    param($objectid,$members,$group)
    write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)"
    $groupmems = Get-MgPrivilegedAccessRoleAssignment -PrivilegedAccessId aadGroups -Filter "resourceId eq '$objectid'" | foreach{
        retrieveactualobject -objectid $_.subjectid -members $members | select *, @{N="nestedgroup";E={$group}}            
    }
    if(!($groupmems)){
        write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)" -ForegroundColor Yellow
        Get-MgGroupMember -GroupId $cleanmem.SubjectId | foreach{
            retrieveactualobject -objectid $_.id -members $members | select *, @{N="nestedgroup";E={$group}}
        }
    }else{
        $groupmems
    }
}

retrieveaadrolemembers -PipelineVariable members | foreach{
    retrieveactualobject -objectid $members.subjectid -members $members -PipelineVariable cleanmem | foreach {
        $cleanmem | select *, nestedgroup
        if($_."@odata.type" -eq "#microsoft.graph.group"){
            expandgroup -objectid $cleanmem.SubjectId -member $members -group $cleanmem.displayName
        }
    }
} | export-csv .\aadrolemembdershipmfastatus.csv -notypeinformation
