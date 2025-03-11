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

$approles = @{}
Get-MgBetaServicePrincipal -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all | select -ExpandProperty approles | foreach{
    try{$approles.add($_.id,$_.value)}catch{}
}
Get-MgBetaServicePrincipal -all -ExpandProperty appRoleAssignedTo | select appid,id, displayname, appRoleAssignedTo | foreach{$sp=$null;$sp=$_
    $_.appRoleAssignedTo | select @{N="spId";E={$sp.id}},
        @{N="appId";E={$sp.appid}},
        @{N="spDisplayName";E={$sp.displayname}},PrincipalId,PrincipalDisplayName,PrincipalType,AppRoleId,@{N="permission";E={$approles[$_.AppRoleId]}}
} | export-csv approleassignment.csv -NoTypeInformation
