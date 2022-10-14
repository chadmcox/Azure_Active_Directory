function createcredhash{
    [cmdletbinding()]
        param()
        $allApps | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDate)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDate
            $_.PasswordCredentials | where {(get-date ($_.EndDate)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDate
        }
        $allSPs  | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDate)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDate
            $_.PasswordCredentials | where {(get-date ($_.EndDate)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDate
        }
}

function returnSPDelegatedPerms{
    [cmdletbinding()]
        param()

    $hash_approles = $allSPs | where {!($_.approles.AllowedMemberTypes -like "*user*")} | `
            select AppDisplayName -ExpandProperty AppRoles | group id -AsHashTable -AsString

    foreach($aadsp in $allSPs){
        Get-AzureADServiceAppRoleAssignedTo -objectid $aadsp.objectid -All $true | foreach{
            $hash_approles[$_.Id] | select `
            @{Name="Scope";Expression={$_.value}}, `
            @{Name="API";Expression={$_.AppDisplayName}}, `
            @{Name="Description";Expression={$_.Description -replace "`n|`r"," " }}, `
            @{Name="Application";Expression={$aadsp.displayname}}, `
            @{Name="ApplicationObjectID";Expression={$aadsp.objectid}}, `
            @{Name="ApplicationPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="ApplicationAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="ApplicationAppId";Expression={$aadsp.Appid}}, `
            @{Name="ApplicationEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="ApplicationValidCred";Expression={$cred_hash.containskey($aadsp.Appid)}}
        }
    }
}

$allSPs = Get-azureadServicePrincipal -all $true
$allApps = Get-azureadApplication -all $true

$cred_hash = createcredhash | group appid -AsHashTable -AsString
returnSPDelegatedPerms | export-csv .\appperms.csv -NoTypeInformation
