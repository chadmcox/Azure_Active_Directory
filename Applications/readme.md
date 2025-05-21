# Service Principals and Applications
## Find Service Principals where all Creds are expired
```
install-module microsoft.graph.users
install-module microsoft.graph.applications
$now = (get-date).AddDays(30)


Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","Application.Read.All"
Select-MgProfile -Name beta

Get-MgServicePrincipal -filter "servicePrincipalType eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | `
    where {($_.PasswordCredentials.EndDateTime) -or ($_.KeyCredentials.EndDateTime)} | `
    where {!($_.PasswordCredentials.endDateTime -gt $now) -and !($_.KeyCredentials.EndDateTime -gt $now)} | select `
        id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
            @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
            @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```

## Find Applications where all Creds are expired
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","Application.Read.All"
Select-MgProfile -Name beta
$now = (get-date).AddDays(30)

Get-MgApplication -all -ExpandProperty owners | `
    where {($_.PasswordCredentials.EndDateTime) -or ($_.KeyCredentials.EndDateTime)} | `
    where {!($_.PasswordCredentials.endDateTime -gt $now) -and !($_.KeyCredentials.EndDateTime -gt $now)} | select `
        id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
            @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```

## Find Enterprise Applications that do not have https in the replyurl
```
Get-mgServicePrincipal -filter "servicePrincipalType eq 'Application'" -all  | `
    where {($_.accountenabled -eq $true) -and ($_.tags -like "*WindowsAzureActiveDirectoryIntegratedApp*")} | `
        select PublisherName, AppId, DisplayName, preferredSingleSignOnMode, signInAudience, ReplyUrls, @{N="tags";E={[string]$($_ | select -expandproperty tags)}} |
        where {$_.ReplyUrls -notlike "*https://*"}
```

## Find Enterprise Applications with no valid reply urls
```
Get-mgServicePrincipal -filter "servicePrincipalType eq 'Application'" -all  | `
    where {($_.accountenabled -eq $true) -and ($_.tags -like "*WindowsAzureActiveDirectoryIntegratedApp*")} | `
        select PublisherName, AppId, DisplayName, preferredSingleSignOnMode, signInAudience, ReplyUrls, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
        @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}} |
        where {$_.ReplyUrls -like "*https://*"} | where {!($_| select -ExpandProperty ReplyUrls | where {$_ -like "http*"} | foreach{try{invoke-webrequest -Uri $_}catch{}})}
```

## Find Enterprise Apps with SAML Signing Cert
```
Get-MgServicePrincipal -filter "servicePrincipalType eq 'Application' and AccountEnabled eq true" -all -ExpandProperty owners | `
    where {$_.KeyCredentials.Usage -eq 'Sign'} | select  appid, PublisherName, displayname, servicePrincipalType, accountEnabled, `
        disabledByMicrosoftStatus, @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
        @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```

## Find all SAML Apps
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","Application.Read.All"
Get-mgServicePrincipal -filter "servicePrincipalType eq 'Application' and preferredSingleSignOnMode eq 'saml'" -all
```

## Get a list of ServicePrincipal Owners
```
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","Application.Read.All"
Select-MgProfile -Name beta
Get-MgServicePrincipal -all -ExpandProperty owners | select `
    id, displayname, servicePrincipalType, AccountEnabled, PublisherName, appid, appdisplayname, `
    @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
```

## Get a list of Applications that allow any user to log into them.
```
Connect-MgGraph -scopes Application.Read.All, Directory.Read.All, Reports.Read.All

#get a list of applications users are signing into
$appids = (Get-MgBetaReportAzureAdApplicationSignInSummary -Period 'D30' | where {$_.SuccessfulSignInCount -gt 0}).id

#get apps because it has created time
$hashapps = Get-MgBetaApplication -Property appId,createdDateTime -all | select appId,createdDateTime | group appid -AsHashTable -AsString

#retrieve list of applications that allow any account to sign into it.
Get-mgBetaServicePrincipal -filter "servicePrincipalType eq 'Application' and accountEnabled eq true" -all `
    -Property tags,appId,id,displayName,appRoleAssignmentRequired,signInAudience,publisherName,appOwnerOrganizationId, preferredSingleSignOnMode,KeyCredentials -ExpandProperty owners  | `
    where {$_.PublisherName -notlike "*Microsoft*" -and $_.appOwnerOrganizationId -ne 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'} | `
    where {$_.tags -contains "WindowsAzureActiveDirectoryIntegratedApp" -and $_.appRoleAssignmentRequired -ne $true -and $_.appId -in $appids} | select `
        appId,id,displayName,appRoleAssignmentRequired, publisherName,signInAudience,preferredSingleSignOnMode, `
        @{N="Owner";E={($_.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}, `
        @{N="tags";E={[string]$_.tags}} | export-csv .\unrestrictedApps.csv -NoTypeInformation
```

## Get a list of Applications with assigned permissions.
```
Connect-MgGraph -scopes Application.Read.All, Directory.Read.All
Select-MgProfile -Name beta

$allsps = Get-mgServicePrincipal -filter "servicePrincipalType eq 'Application' and accountEnabled eq true" -all
$hashroles = $allsps | select -ExpandProperty AppRoles | select id,value -Unique | group id -AsHashTable -AsString

Get-mgServicePrincipal -filter "accountEnabled eq true" -all -ExpandProperty owners | foreach{
    $aadsp = $null; $aadsp=$_
    Get-MgServicePrincipalAppRoleAssignment -serviceprincipalid $_.id | foreach{$appra=$null;$appra=$_
        $hashroles[$($appra.appRoleId)] | select -ExpandProperty value -pv perm | select `
            @{Name="DisplayName";Expression={$($appra.PrincipalDisplayName)}}, `
             @{Name="Permission to";Expression={$($appra.ResourceDisplayName)}}, `
             @{Name="Scope";Expression={$($_)}}, `
             @{N="Owner";E={($aadsp.owners.id | foreach{Get-mguser -userId $_}).UserPrincipalName -join(",")}}
    }
} | export-csv .\apppermissions.csv -notypeinformation
```
