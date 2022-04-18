# Service Principals and Applications
## Find Service Principals where all Creds are expired
```
install-module microsoft.graph.users
install-module microsoft.graph.applications


Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Select-MgProfile -Name beta

Get-MgServicePrincipal -filter "servicePrincipalType eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | `
    where {($_.PasswordCredentials.EndDateTime) -or ($_.KeyCredentials.EndDateTime)} | `
    where {!($_.PasswordCredentials.endDateTime -gt $now) -and !($_.KeyCredentials.EndDateTime -gt $now)} | select `
        id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
            @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```

## Find Applications where all Creds are expired
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Select-MgProfile -Name beta
Get-MgApplication -all -ExpandProperty owners | `
    where {($_.PasswordCredentials.EndDateTime) -or ($_.KeyCredentials.EndDateTime)} | `
    where {!($_.PasswordCredentials.endDateTime -gt $now) -and !($_.KeyCredentials.EndDateTime -gt $now)} | select `
        id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
            @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```
