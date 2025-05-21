$exclude = "Office 365 Exchange Online","Microsoft Teams Services","Office 365 SharePoint Online","Yammer","Microsoft Office 365 Portal"

function getRoleMembersfromAAD{
    [CmdletBinding()]
    param()
    Get-AzureADDirectoryRole | where displayname -like "*Administrator" | Get-AzureADDirectoryRoleMember -pv mem | `
        select objecttype, objectid, userprincipalname, appid -Unique

}

getRoleMembersfromAAD -pv mem | foreach{
    if($mem.objecttype -eq "User"){write-host "$($mem.userPrincipalName)"
        Get-AzureADAuditDirectoryLogs -Filter "initiatedBy/user/userPrincipalName eq '$($mem.userPrincipalName)'" -all $true | `
            where {$_.InitiatedBy.user.Displayname -notin $exclude} | foreach{ 
            if($_.ActivityDisplayName -in "Add member to group","Remove member from group","Add owner to group","Add member to role","Add owner to service principal"){
                $_ | select ActivityDateTime, Result, ActivityDisplayName, `
                    @{N="InitiatedBy";E={if($_.InitiatedBy.user.userPrincipalName){$_.InitiatedBy.user.userPrincipalName}elseif($_.InitiatedBy.app.DisplayName){$_.InitiatedBy.app.DisplayName}else{$_.InitiatedBy.user.DisplayName}}}, `
                    @{N="Target";E={(($_.targetresources.ModifiedProperties | where {$_.DisplayName -eq "Group.DisplayName"}).newvalue).replace('"','')}}, `
                    @{N="PrincipalName";E={[string]($_).TargetResources.UserPrincipalName}}
            }else{
                $_ | select ActivityDateTime, Result, ActivityDisplayName, `
                @{N="InitiatedBy";E={if($_.InitiatedBy.user.UserPrincipalName){$_.InitiatedBy.user.UserPrincipalName}elseif($_.InitiatedBy.app.DisplayName){$_.InitiatedBy.app.DisplayName}else{$_.InitiatedBy.user.Displayname}}}, `
                @{N="Target";E={if([string]($_).TargetResources.DisplayName){[string]($_).TargetResources.DisplayName}else{[string]($_).TargetResources.UserPrincipalName}}}
            }}}

    Start-Sleep -Seconds 3
} 
