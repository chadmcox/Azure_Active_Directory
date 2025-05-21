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

function transitivemember-count{
    param($guid)
    Get-MgBetaGroupTransitiveMemberCount -GroupId $guid -ConsistencyLevel "Eventual"
}

write-host "Exporting Groups"
Get-MgBetaGroup -all -property Id, Displayname, OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,GroupTypes, IsAssignableToRole, `
    MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId, owners | select Id, Displayname, OnPremisesSyncEnabled,mailEnabled, `
    SecurityEnabled,GroupTypes, IsAssignableToRole, MembershipRuleProcessingState, ExpirationDateTime, CreatedDateTime, CreatedByAppId, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}}, `
    @{n='TransitiveMemberCount';e={transitivemember-count -guid $_.id}} | `
        export-csv .\groups.csv -NoTypeInformation
