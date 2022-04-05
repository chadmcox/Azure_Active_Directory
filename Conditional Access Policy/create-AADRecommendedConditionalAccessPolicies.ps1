Connect-MgGraph -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.ReadWrite.All", "Directory.AccessAsUser.All"

#Create Tor Exit Note Named Locations
$body = (invoke-webrequest -uri "https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/JSON/Tor_Exit_Notes.json").content | convertfrom-json
New-MgIdentityConditionalAccessNamedLocation -BodyParameter ($body | convertto-json)
