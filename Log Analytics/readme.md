# KQL Basics

* tabular expression statement, which means both its input and output consist of tables or tabular datasets. Tabular statements contain zero or more operators
* each of which starts with a tabular input and returns a tabular output. Operators are sequenced by a | (pipe).
* Data flows, or is piped, from one operator to the next.
* It's like a funnel, where you start out with an entire data table. Each time the data passes through another operator, it is filtered, rearranged, or summarized.
* Because the piping of information from one operator to another is sequential, the query operator order is important and can affect both results and performance. At the end of the funnel, you're left with a refined output.

To retrieve data from a table you can simply run the name of the table:
```
SigninLogs 

```
This is a basic structure 
```
SigninLogs 
| where UserPrincipalName == "bob@contoso.com"
| project UserPrincipalName, AppDisplayName, CreatedDateTime

```

* KQL is extremely case sensitive.  the syntax of the command and the values being searched for are case sennsitive.

## Filtering

* Always start with a time filter
```
SigninLogs
| where TimeGenerated > ago(30d)
```

## SigninLogs - DeviceDetail
```
SigninLogs
| extend browser = tostring(parse_json(DeviceDetail).browser) 
| extend operatingSystem = tostring(parse_json(DeviceDetail).operatingSystem) 
| extend deviceName = tostring(parse_json(DeviceDetail).displayName)
| extend isCompliant = tostring(parse_json(DeviceDetail).isCompliant) 
| extend isManaged = tostring(parse_json(DeviceDetail).isManaged)
| extend trustType = tostring(parse_json(DeviceDetail).trustType)
```

## SigninLogs - LocationDetails
```
SigninLogs
| extend city = tostring(parse_json(LocationDetails).city)
| extend countryOrRegion = tostring(parse_json(LocationDetails).countryOrRegion)
| extend state = tostring(parse_json(LocationDetails).state)
```

## SigninLogs - NetworkLocationDetails
```
//is the authentication coming from a trusted location
SigninLogs
| extend TrustedLocation = tostring(iff(NetworkLocationDetails contains 'trustedNamedLocation', 'trustedNamedLocation',''))

//retrieve the first network named location
SigninLogs
| extend NetworkLocation = tostring(parse_json(NetworkLocationDetails)[0].networkNames[0])

//expand and retrieve each network named location in the atteribute
SigninLogs
| extend Parsed_NetworkLocationDetails = parse_json(NetworkLocationDetails)
| mv-expand Parsed_NetworkLocationDetails
| extend networkType = tostring(Parsed_NetworkLocationDetails.networkType), networkName = tostring(Parsed_NetworkLocationDetails.networkNames[0])

```
