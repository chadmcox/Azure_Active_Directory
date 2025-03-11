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

write-host "Exporting Guest"
Get-MgBetaUser -Filter "userType eq 'Guest'" -all -all  -Property id,displayName,signInActivity,userPrincipalName,SignInType, `
    userType,onPremisesSyncEnabled,createdDateTime,accountEnabled,passwordPolicies,mail,lastPasswordChangeDateTime,externalUserState,externalUserStateChangeDateTime | `
    select id,displayName,userPrincipalName,userType,externalUserState,onPremisesSyncEnabled,createdDateTime,accountEnabled,mail,lastPasswordChangeDateTime,passwordPolicies, `
        @{N='lastSuccessfulSignInDateTime';E={$_.signInActivity.lastSuccessfulSignInDateTime}}, @{N='LastSignInDateTime';E={$_.signInActivity.LastSignInDateTime}}, `
        @{N='LastNonInteractiveSignInDateTime';E={$_.signInActivity.LastNonInteractiveSignInDateTime}},
        @{Name="externalUserStateChangeDateTime";Expression={(get-date $_.externalUserStateChangeDateTime).tostring('yyyy-MM-dd')}},
        @{Name="Domain";Expression={($_.mail -split("@"))[1]}}, @{Name="UnifiedGroupMember";Expression={$_.memberOf.groupTypes -contains "Unified"}}, `
        @{Name="SignInType";Expression={($_.identities | where {$_.SignInType -eq "federated"}).Issuer}} | export-csv .\guests.csv -NoTypeInformation
