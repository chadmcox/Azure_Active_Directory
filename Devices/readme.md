# First connect to graph with the Microsoft.Graph.Beta cmdlets
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"

```

# Get a basic list of devices and the registration and trust type
```
Get-MgBetaDevice -all | Select `
    displayname, operatingsystem, OperatingSystemVersion, accountenabled, profiletype, trusttype, `
    onPremisesSyncEnabled, @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
    @{N="enrollmentProfileName";Expression={$_.AdditionalProperties.enrollmentProfileName}}, `
    @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}}, `
    @{N="ApproximateLastSignInDateTime";Expression={(get-date $_.ApproximateLastSignInDateTime).tostring('yyyy-MM-dd')}} | `
        export-csv .\devices.csv -NoTypeInformation
```

# Get a list of all windows devices and the registration and trust type
```
Get-MgBetaDevice -filter "operatingSystem eq 'Windows'" -all | Select `
    displayname, operatingsystem, accountenabled, profiletype, trusttype, `
    @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
    @{N="enrollmentProfileName";Expression={$_.AdditionalProperties.enrollmentProfileName}}, `
    @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}} | `
        export-csv .\windowsdevices.csv -NoTypeInformation
```

# Get a list and filter on windows that are Azure AD Joined
```
Get-MgBetaDevice -filter "operatingSystem eq 'Windows' and trustType eq 'AzureAd'" -all | Select `
    displayname, operatingsystem, accountenabled, profiletype, trusttype, `
    @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
    @{N="enrollmentProfileName";Expression={$_.AdditionalProperties.enrollmentProfileName}}, `
    @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}} | `
        export-csv .\windowsaadjdevices.csv -NoTypeInformation
```
# Get a list Windows devices with the last time they reported a sign in
```
Get-MgBetaDevice -filter "operatingSystem eq 'Windows'" -all | Select `
    displayname, operatingsystem, OperatingSystemVersion, accountenabled, profiletype, trusttype, `
    onPremisesSyncEnabled, @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
    @{N="enrollmentProfileName";Expression={$_.AdditionalProperties.enrollmentProfileName}}, `
    @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}}, `
    @{N="ApproximateLastSignInDateTime";Expression={(get-date $_.ApproximateLastSignInDateTime).tostring('yyyy-MM-dd')}} | `
        export-csv .\windowsdevices.csv -NoTypeInformation
