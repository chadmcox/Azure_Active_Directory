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
Get-MgBetaServicePrincipal -Filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all | foreach{
    try{$approles.add($_.id,$_.Displayname)}catch{}
}

Get-MGBetaServicePrincipal -filter "serviceprincipaltype eq 'Application' and AccountEnabled eq true" -all | foreach{$aadsp=$null;$aadsp=$_
    Get-MgBetaServicePrincipalOauth2PermissionGrant -ServicePrincipalId $aadsp.id -all | foreach{$oauth2=$null;$oauth2=$_
    $oauth2.scope -split " " | select `
            @{Name="App";Expression={$aadsp.displayname}}, `
            @{Name="AppObjectID";Expression={$aadsp.ID}}, `
            @{Name="AppPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="AppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="AppId";Expression={$aadsp.Appid}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="PrincipalId";Expression={$oauth2.PrincipalId}}, `
            @{Name="API";Expression={$approles[$oauth2.resourceId]}}, `
            @{Name="Consenttype";Expression={$oauth2.consentType}} | where {!($_.Scope -eq "")}
    }
} | export-csv .\applicationconsents.csv -notypeinformation
