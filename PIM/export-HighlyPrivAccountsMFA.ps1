Connect-MgGraph

$critical_role_template_guids = @("62e90394-69f5-4237-9190-012177145e10", ` #Company Administrator / Global Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814", ` #Privileged Role Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d", ` #Security Administrator
    "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", ` #Application Administrator
    "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", ` #Privileged Authentication Administrator
    "158c047a-c907-4556-b7ef-446551a6b5f7", ` #Cloud Application Administrator
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", ` #Conditional Access Administrator
    "c4e39bd9-1100-46d3-8c65-fb160da0071f", ` #Authentication Administrator
    "29232cdf-9323-42fd-ade2-1d097af3e4de", ` #Exchange Administrator
    "8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2", ` #Hybrid Identity Administrator
    "966707d0-3269-4727-9be2-8c3a10f19b9d", ` #Password Administrator
    "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", ` #SharePoint Administrator
    "fe930be7-5e62-47db-91af-98c3a49a38b1", ` #User Administrator
    "729827e3-9c14-49f7-bb1b-9608f156bbb8") #Helpdesk Administrator

$context = get-mgcontext

write-host "Export Direct PIM Membership"
$roledirectmembers = Get-MgBetaPrivilegedAccessRoleDefinition -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)'" | `
    where {$_.TemplateId -in $critical_role_template_guids} -PipelineVariable role | foreach{
    Get-MgBetaPrivilegedAccessRoleAssignment -PrivilegedAccessId AADRoles -Filter "resourceId eq '$($context.TenantId)' and roleDefinitionId eq '$($role.id)'" | foreach{$mem=$null;$mem=$_ 
        Get-MgBetaDirectoryObject -DirectoryObjectId $_.subjectid | select -ExpandProperty AdditionalProperties | Convertto-Json | `
            ConvertFrom-Json | select @{N="roleId";E={$role.Id}}, @{N="roleName";E={$role.DisplayName}}, @{N="SubjectId";E={$mem.SubjectId}}, displayname, "@odata.type"}
}
write-host "Expand PIM Membership"
$rolemembers = $roledirectmembers | foreach{$rm=$null;$rm=$_
    if($rm."@odata.type" -eq "#microsoft.graph.group"){
        Get-MgBetaPrivilegedAccessRoleAssignment -PrivilegedAccessId aadGroups -Filter "resourceId eq '$($rm.SubjectId)'" | foreach{ $mem=$null;$mem=$_ 
            Get-MgBetaDirectoryObject -DirectoryObjectId $_.subjectid | select -ExpandProperty AdditionalProperties | Convertto-Json | `
            ConvertFrom-Json | select @{N="roleId";E={$rm.roleId}}, @{N="roleName";E={$rm.roleName}}, @{N="SubjectId";E={$mem.SubjectId}}, displayname, "@odata.type"}
    }else{
        $_
    }
}
write-host "Retrieving mfa info"

$rolemembers | foreach{$mem=$null;$mem=$_
    if($mem."@odata.type" -eq "#microsoft.graph.user"){
        write-host "Gathering infor for $($mem.displayname)"
        $reg=$null;$reg = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId $mem.SubjectId
        $mem | select `
            @{N="roleId";E={$mem.roleId}}, `
            @{N="roleName";E={$mem.roleName}}, `
            @{N="SubjectId";E={$mem.SubjectId}}, `
            @{N="displayname";E={$mem.displayname}}, `
            @{N="IsMfaCapable";E={$reg.IsMfaCapable}}, `
            @{N="IsMfaRegistered";E={$reg.IsMfaRegistered}}, `
            @{N="IsPasswordlessCapable";E={$reg.IsPasswordlessCapable}}, `
            @{N="microsoftAuthenticator";E={$reg.MethodsRegistered -contains "microsoftAuthenticatorPush"}}, `
            @{N="microsoftAuthenticatorPasswordless";E={$reg.MethodsRegistered -contains "microsoftAuthenticatorPasswordless"}}, `
            @{N="windowsHelloForBusiness";E={$reg.MethodsRegistered -contains "windowsHelloForBusiness"}}, `
            @{N="fido2";E={$reg.MethodsRegistered -contains "fido2"}}, `
            @{N="Phone";E={$reg.MethodsRegistered -like "*Phone*"}}
    }
} | export-csv ".\priv_account_mfa.csv" -NoTypeInformation
