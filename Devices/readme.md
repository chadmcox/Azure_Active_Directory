# First connect to graph with the microsoft.graph cmdlets
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Select-MgProfile -Name beta
```

# Get a basic list of devices and the registration and trust type
```
Get-MgDevice -all | Select displayname, operatingsystem, accountenabled, profiletype, trusttype, `
  @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
  @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}} | export-csv .\aaddevices.csv -NoTypeInformation
```

# Get a list and filter on windows that are Azure AD Joined
```
Get-MgDevice -filter "operatingSystem eq 'Windows' and trustType eq 'AzureAd'" -all | Select `
    displayname, operatingsystem, accountenabled, profiletype, trusttype, `
    @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
    @{N="enrollmentProfileName";Expression={$_.AdditionalProperties.enrollmentProfileName}}, `
    @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}} | `
        export-csv .\windowsaadjdevices.csv -NoTypeInformation
```
