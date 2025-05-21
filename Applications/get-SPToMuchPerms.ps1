param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
$sps = Get-MgBetaServicePrincipal -all
$graph_hash = $sps | where {$_.approles.AllowedMemberTypes -like "Application"} | select @{Name="Application";Expression={$_.displayname}} -ExpandProperty AppRoles | group id -AsHashTable -AsString
$sps | where {$_.approles.AllowedMemberTypes -like "Application"} -PipelineVariable s | foreach{
    Get-MgBetaServicePrincipalAppRoleAssignedTo -ServicePrincipalId $s.id -all | 
        where {($graph_hash[$_.AppRoleId]).value -like "*write*"} | foreach{$sp=$null;$sp=$_
        Get-MgBetaServicePrincipalOwner -ServicePrincipalId $_.PrincipalId | select -ExpandProperty AdditionalProperties | `
            convertto-json | convertfrom-json | foreach{$owner=$null;$owner=$_
            $graph_hash[$sp.AppRoleId] | where {$_.value -like "*write*" -and $_.application -eq $s.displayname} | select `
            @{Name="Owner";Expression={$owner.displayname}}, `
            @{Name="OwnerUPN";Expression={$owner.userPrincipalName}}, `
            @{Name="PrincipalDisplayName";Expression={$sp.PrincipalDisplayName}}, `
            @{Name="ResourceDisplayName";Expression={$sp.ResourceDisplayName}}, `
            value, Description            
        }
        }
    } | export-csv .\sensitive_permissions_application_owners.csv -NoTypeInformation
