<#PSScriptInfo
.VERSION 2023.4.11
.GUID 65460b6b-943b-4ac7-780c-91e57d9db760
.AUTHOR Chad.Cox@microsoft.com
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
this looks for policy from the following articles

.EXAMPLE
#>
param($path="$env:USERPROFILE\downloads")
cd $path
$starttime = Get-Date

Import-Module Microsoft.Graph.Identity.Governance

function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All","Group.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All","User.Read.All", `
        "UserAuthenticationMethod.Read.All" -Environment $mg_env.name
    Select-MgProfile -Name "beta"
}
function retrieveaadpimrolemembers{
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
function retrieveaaddirrolemembers{
    [cmdletbinding()] 
    param()
    Get-MgDirectoryRole -all | foreach{$role=$null;$role=$_
    Get-MgDirectoryRoleMember -DirectoryRoleId $_.id -All | select @{N="roleId";E={$role.Id}}, `
        @{N="roleName";E={$role.DisplayName}}, @{N="SubjectId";E={$_.ID}}, AssignmentState,Permanant 
    }
}

function retrieveactualobject{
    [cmdletbinding()] 
    param($objectid,$members)
    write-host "Translating $objectid"
    if(!($script:hash_alreadyretrievedobject.containskey($objectid))){ 
        $foundobject = Get-MgDirectoryObject -DirectoryObjectId $objectid | select -ExpandProperty AdditionalProperties | Convertto-Json | ConvertFrom-Json | select `
            "@odata.type", displayName,userprincipalname, @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, `
                @{N="SubjectId";E={$objectid}}, @{N="AssignmentState";E={$members.AssignmentState}}, `
                @{N="IsMfaRegistered";E={(Get-MgReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId $objectid).IsMfaRegistered}}, `
                @{N="Permanant";E={$members.Permanant}}
        try{$script:hash_alreadyretrievedobject += $foundobject | group SubjectId -AsHashTable -AsString}catch{}
        $foundobject
    }else{
        write-host "already translated" -ForegroundColor Gray
        $script:hash_alreadyretrievedobject[$objectid] | select `
            "@odata.type", displayName,userprincipalname, @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, `
                @{N="SubjectId";E={$objectid}}, @{N="AssignmentState";E={$members.AssignmentState}}, `
                @{N="IsMfaRegistered";E={(Get-MgReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId $objectid).IsMfaRegistered}}, `
                @{N="Permanant";E={$members.Permanant}}
    }
}
function expandgroup{
    [cmdletbinding()] 
    param($objectid,$members,$group)
    write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)"
    if(!($script:hash_alreadyretrieved.containskey($cleanmem.DisplayName))){
        $groupmems = Get-MgPrivilegedAccessRoleAssignment -PrivilegedAccessId aadGroups -Filter "resourceId eq '$objectid'" | foreach{$pag=$null;$pag=$_
            #originally this was taking the pim values from the group, now it is taking from the user.
            $members.Permanant = $(if($pag.AssignmentState -eq "Active" -and $pag.EndDateTime -eq $null){$true}else{$false})
            $members.AssignmentState = $pag.AssignmentState
            retrieveactualobject -objectid $_.subjectid -members $members | select *, @{N="nestedgroup";E={$group}}            
        }
        if(!($groupmems)){
            write-host "Exporting $($cleanmem.DisplayName) $($cleanmem.id)" -ForegroundColor Yellow
            $groupmems = Get-MgGroupMember -GroupId $cleanmem.SubjectId | foreach{
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
            @{N="roleId";E={$members.roleId}}, @{N="roleName";E={$members.roleName}}, SubjectId, AssignmentState,IsMfaRegistered,Permanant,nestedgroup
    }
}

$script:hash_alreadyretrieved = @{}
$script:hash_alreadyretrievedobject = @{}

login-MSGraph
$context = get-mgcontext

write-host "Exporting PIM AAD Role Memberships"
retrieveaadpimrolemembers -PipelineVariable members | foreach{
    retrieveactualobject -objectid $members.subjectid -members $members -PipelineVariable cleanmem | foreach {
        $cleanmem | select *, nestedgroup
        if($_."@odata.type" -eq "#microsoft.graph.group"){
            expandgroup -objectid $cleanmem.SubjectId -member $members -group $cleanmem.displayName
        }
    }
} | export-csv .\aadpimrolemembership.csv -notypeinformation



write-host "Exporting AAD Role Memberships"
retrieveaaddirrolemembers  -PipelineVariable members | foreach{
    retrieveactualobject -objectid $members.subjectid -members $members -PipelineVariable cleanmem | foreach {
        $cleanmem | select *, nestedgroup
        if($_."@odata.type" -eq "#microsoft.graph.group"){
            expandgroup -objectid $cleanmem.SubjectId -member $members -group $cleanmem.displayName
        }
    }
} | export-csv .\aaddirectoryrolemembership.csv -notypeinformation


write-host "Complete in $((New-TimeSpan -Start $starttime -End (get-date)).minutes) minutes, files can be found here $path"
