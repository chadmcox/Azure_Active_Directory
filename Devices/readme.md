
# Get a basic list of devices and the registration and trust type
```
Get-MgDevice -all | Select displayname, operatingsystem, accountenabled, profiletype, trusttype, `
  @{N="enrollmentType";Expression={$_.AdditionalProperties.enrollmentType}}, `
  @{N="createdDateTime";Expression={(get-date $_.AdditionalProperties.createdDateTime).tostring('yyyy-MM-dd')}} | export-csv .\aaddevices.csv -NoTypeInformation
```
