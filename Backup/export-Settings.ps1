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
Get-MgBetaPolicyAuthenticationStrengthPolicy | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

Get-MgBetaPolicyCrossTenantAccessPolicyDefault | convertto-json -depth 99 | out-file .\CrossTenantAccessPolicyDefault.txt

"FederationConfiguration" | out-file .\configuration.txt -Append
Get-MgDirectoryFederationConfiguration -all | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"ActivityBasedTimeoutPolicy" | out-file .\configuration.txt -Append
Get-MgBetaPolicyActivityBasedTimeoutPolicy | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"AuthorizationPolicy" | out-file .\configuration.txt -Append
Get-MgBetaPolicyAuthorizationPolicy | select * -ExcludeProperty AdditionalProperties | fl |  out-file .\configuration.txt -Append

"DeviceRegistrationPolicy LocalAdminPassword" | out-file .\configuration.txt -Append
Get-MgBetaPolicyDeviceRegistrationPolicy | select DisplayName,MultiFactorAuthConfiguration,UserDeviceQuota |  out-file .\configuration.txt -Append

"DeviceRegistrationPolicy AzureAdJoin" | out-file .\configuration.txt -Append
Get-MgBetaPolicyDeviceRegistrationPolicy | select -ExpandProperty AzureAdJoin |  out-file .\configuration.txt -Append

"DeviceRegistrationPolicy azureADRegistration" | out-file .\configuration.txt -Append
Get-MgBetaPolicyDeviceRegistrationPolicy | select -ExpandProperty azureADRegistration |  out-file .\configuration.txt -Append

"DeviceRegistrationPolicy LocalAdminPassword" | out-file .\configuration.txt -Append
Get-MgBetaPolicyDeviceRegistrationPolicy | select -ExpandProperty LocalAdminPassword |  out-file .\configuration.txt -Append

"SecurityDefaultEnforcementPolicy" | out-file .\configuration.txt -Append
Get-MgBetaPolicyIdentitySecurityDefaultEnforcementPolicy | select * -ExcludeProperty AdditionalProperties  | fl |  out-file .\configuration.txt -Append
