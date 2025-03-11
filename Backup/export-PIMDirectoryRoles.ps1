param($defaultpath="$env:USERPROFILE\downloads",$pwdnochangedindays = 480)
cd $defaultpath

function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Policy.Read.All","User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All","Group.Read.All","Application.Read.All", "AuditLog.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All" -Environment $mg_env.name
}

#login
login-MSGraph

function retrieveaadpimrolemembers{
    [cmdletbinding()] 
    param()
    Get-MgBetaPrivilegedAccessRoleDefinition -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | foreach{
        $role = $null; $role = $_
        write-host "Exporting $($role.DisplayName) $($role.id)"
        Get-MgBetaPrivilegedAccessRoleAssignment -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)' and roleDefinitionId eq '$($role.id)'" | `
            select @{N="roleId";E={$role.Id}}, @{N="roleName";E={$role.DisplayName}}, SubjectId, AssignmentState, `
                @{N="Permanant";E={if($_.AssignmentState -eq "Active" -and $_.EndDateTime -eq $null){$true}else{$false}}}
    }
    
}

function retrieveactualobject{
    [cmdletbinding()] 
    param($objectid,$members)
    write-host "Translating $objectid"
    if(!($script:hash_alreadyretrievedobject.containskey($objectid))){ 
        $foundobject = Get-MgBetaDirectoryObject -DirectoryObjectId $objectid | select -ExpandProperty AdditionalProperties | Convertto-Json | ConvertFrom-Json | select `
            "@odata.type", displayName,userprincipalname, @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, `
                @{N="SubjectId";E={$objectid}}, @{N="AssignmentState";E={$members.AssignmentState}},onPremisesSyncEnabled, `
                @{N="Permanant";E={$members.Permanant}}
        try{$script:hash_alreadyretrievedobject += $foundobject | group SubjectId -AsHashTable -AsString}catch{}
        $foundobject
    }else{
        write-host "already translated" -ForegroundColor Gray
        $script:hash_alreadyretrievedobject[$objectid] | select `
            "@odata.type", displayName,userprincipalname, @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, `
                @{N="SubjectId";E={$objectid}}, @{N="AssignmentState";E={$members.AssignmentState}},onPremisesSyncEnabled, `
                @{N="Permanant";E={$members.Permanant}}
    }
}
function expandgroup{
    [cmdletbinding()] 
    param($objectid,$members,$group)
    write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)"
    if(!($script:hash_alreadyretrieved.containskey($cleanmem.DisplayName))){
        $groupmems = Get-MgBetaPrivilegedAccessRoleAssignment -PrivilegedAccessId aadGroups -Filter "resourceId eq '$objectid'" | foreach{$pag=$null;$pag=$_
            #originally this was taking the pim values from the group, now it is taking from the user.
            $members.Permanant = $(if($pag.AssignmentState -eq "Active" -and $pag.EndDateTime -eq $null){$true}else{$false})
            $members.AssignmentState = $pag.AssignmentState
            retrieveactualobject -objectid $_.subjectid -members $members | select *, @{N="nestedgroup";E={$group}}            
        }
        if(!($groupmems)){
            write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)" -ForegroundColor Yellow
            $groupmems = Get-MgBetaGroupMember -GroupId $cleanmem.SubjectId | foreach{
                retrieveactualobject -objectid $_.id -members $members | select *, @{N="nestedgroup";E={$group}}
            }
            if($groupmems){
                try{$script:hash_alreadyretrieved += $groupmems | group nestedgroup -AsHashTable -AsString}catch{}
                $groupmems
            }
        }else{
            #I assume this works no honest Idea
            try{$script:hash_alreadyretrieved += $groupmems | group nestedgroup -AsHashTable -AsString}catch{}
            $groupmems
        }
    }else{
        #goal is to cache groups already been enumerated and to keep adding to them.
        write-host "already exported" -ForegroundColor Gray
        $script:hash_alreadyretrieved[$cleanmem.DisplayName] | select '@odata.type',displayName, userPrincipalName, `
            @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, SubjectId, AssignmentState,onPremisesSyncEnabled,Permanant,nestedgroup
    }
}

$script:hash_alreadyretrieved = @{}
$script:hash_alreadyretrievedobject = @{}


write-host "Exporting PIM AAD Role Memberships"
retrieveaadpimrolemembers -PipelineVariable members | foreach{
    retrieveactualobject -objectid $members.subjectid -members $members -PipelineVariable cleanmem | foreach {
        $cleanmem | select *, nestedgroup
        if($_."@odata.type" -eq "#microsoft.graph.group"){
            expandgroup -objectid $cleanmem.SubjectId -member $members -group $cleanmem.displayName
        }
    }
} | export-csv .\pimrolemembers.csv -notypeinformation
