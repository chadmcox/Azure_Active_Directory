param($defaultpath="$env:USERPROFILE\downloads",$pwdnochangedindays = 480)
cd $defaultpath

function login-MSGraph{
    Get-MgEnvironment | select name | out-host
    $selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
    if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
    $mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

    $script:graphendpoint = $mg_env.GraphEndpoint

    Connect-MgGraph -Scopes "Policy.Read.All","User.ReadBasic.All", "User.Read.All","Directory.Read.All","Directory.AccessAsUser.All","Group.Read.All","Application.Read.All", "AuditLog.Read.All","PrivilegedAccess.Read.AzureAD", `
        "PrivilegedAccess.Read.AzureADGroup","PrivilegedAccess.Read.AzureResources","RoleManagement.Read.All","OnPremDirectorySynchronization.Read.All","IdentityRiskyUser.Read.All" -Environment $mg_env.name
}

#login
login-MSGraph

"FeatureRolloutPolicy" | out-file .\configuration.txt
Get-MgPolicyFeatureRolloutPolicy -all | out-file .\configuration.txt -Append

"License" | out-file .\configuration.txt -Append
Get-MgBetaSubscribedSku -all | select SkuPartNumber,ConsumedUnits, @{Name="PrepaidUnits Enabled";Expression={$_.PrepaidUnits.Enabled}} | select * -ExcludeProperty AdditionalProperties | fl | out-file .\configuration.txt -Append

"OnPremiseSynchronization Feature" | out-file .\configuration.txt -Append
Get-MgBetaDirectoryOnPremiseSynchronization | select -ExpandProperty Features | convertto-json -Depth 99 | ConvertFrom-json |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"OnPremiseSynchronization Configuration" | out-file .\configuration.txt -Append
Get-MgBetaDirectoryOnPremiseSynchronization | select -ExpandProperty configuration | convertto-json -Depth 99 | ConvertFrom-json |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"Organization Info" | out-file .\configuration.txt -Append
Get-MgBetaOrganization | select BusinessPhones, city, country, countryletter, createddatetime, defaultusagelocation, displayname, onpremise*, postalcode, prefferedlanguage, state, street, TenantType |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"AdminConsentRequestPolicy" | out-file .\configuration.txt -Append
Get-MgPolicyAdminConsentRequestPolicy |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"AuthenticationMethodConfigurationsy" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select -ExpandProperty AuthenticationMethodConfigurations |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"MicrosoftAuthenticatorPlatformSettings" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select  -ExpandProperty MicrosoftAuthenticatorPlatformSettings | select -ExpandProperty EnforceAppPin |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"AuthenticationMethodsRegistrationCampaign" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select  -ExpandProperty RegistrationEnforcement | select -ExpandProperty AuthenticationMethodsRegistrationCampaign |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"ReportSuspiciousActivitySettings" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select  -ExpandProperty ReportSuspiciousActivitySettings |select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"SystemCredentialPreferences" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select  -ExpandProperty SystemCredentialPreferences | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"PolicyMigrationState" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthenticationMethodPolicy | select PolicyMigrationState,PolicyVersion,ReconfirmationInDays -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"AuthenticationStrengthPolicy" | out-file .\configuration.txt -Append
Get-MgPolicyAuthenticationStrengthPolicy | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

Get-MgPolicyCrossTenantAccessPolicyDefault | convertto-json -depth 99 | out-filter .\CrossTenantAccessPolicyDefault.txt
