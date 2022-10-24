param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}

cd $defaultpath
function getFromMSGraph{
    [cmdletbinding()] 
    param($uri)
    do{$results = $null
        for($i=0; $i -le 3; $i++){
            try{
                $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
                break
            }catch{#if this fails it is going to try to authenticate again and rerun query
                if(($_.Exception.response.statuscode -eq "TooManyRequests") -or ($_.Exception.Response.StatusCode.value__ -eq 429)){
                    #if this hits up against to many request response throwing in the timer to wait the number of seconds recommended in the response.
                    write-host "Error: $($_.Exception.response.statuscode), trying again $i of 3"
                    Start-Sleep -Seconds $_.Exception.response.headers.RetryAfter.Delta.seconds
                }elseif(($_.Exception.response.statuscode -eq "BadRequest") -or ($_.Exception.Response.StatusCode.value__ -eq 400)){
                    $i++
                }
            }
        }
        if($results){
                if($results | get-member | where {$_.name -eq "value"}){
                    $results.value
                }else {
                    $results
                }
            }
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}
function createcredhash{
    [cmdletbinding()]
        param()
        $aadApps | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDateTime)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDateTime
            $_.PasswordCredentials | where {(get-date ($_.EndDateTime)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDateTime
        }
        $aadsps  | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDateTime)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDateTime
            $_.PasswordCredentials | where {(get-date ($_.EndDateTime)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDateTime
        }
}
function returnSPPerms{
    [cmdletbinding()]
        param()

    $hash_approles = $aadsps | where {$_.approles.AllowedMemberTypes -like "Application"} | `
            select -ExpandProperty AppRoles | group id -AsHashTable -AsString

    foreach($aadsp in $aadsps){
        write-host "$($aadsp.displayname)"
        $spra_uri = "https://graph.microsoft.com/beta/servicePrincipals/$($aadsp.id)/appRoleAssignments"
        $aadsp | select -ExpandProperty appRoleAssignments -pv approle | foreach{
            $hash_approles[$_.appRoleId] | select `
            @{Name="Principal";Expression={$aadsp.displayname}}, `
            @{Name="PrincipalID";Expression={$aadsp.ID}}, `
            @{Name="PrincipalPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="PrincipalAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="PrincipalAppId";Expression={$aadsp.Appid}}, `
            @{Name="PrincipalEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="ServicePrincipalType";Expression={$aadsp.ServicePrincipalType}}, `
            @{Name="PrincipalValidCred";Expression={$cred_hash.containskey($aadsp.Appid)}}, `
            @{Name="Scope";Expression={$_.value}}, `
            @{Name="API";Expression={$approle.ResourceDisplayName}}, `
            @{Name="Description";Expression={$_.Description -replace "`n|`r"," " }}
        }
    }
}

write-host "Retrieving every Service Principal"
$sp_uri = "https://graph.microsoft.com/beta/servicePrincipals?`$expand=appRoleAssignments"
$aadsps = getFromMSGraph -uri $sp_uri
write-host "Retrieving every App"
$app_uri = "https://graph.microsoft.com/beta/applications"
$aadApps = getFromMSGraph -uri $app_uri | select appid, KeyCredentials, PasswordCredentials
write-host "Building credential hash"
$cred_hash = createcredhash | group appid -AsHashTable -AsString
write-host "Building Report"
returnSPPerms | export-csv .\aad_appperms.csv -NoTypeInformation

write-host "Results found here $defaultpath"
