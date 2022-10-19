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


function exportcreds{
    [cmdletbinding()]
        param()
        @($aadApps,$aadSps) | select * -pv aadsp | select @{Name="Principal";Expression={$aadsp.displayname}}, `
                @{Name="PrincipalID";Expression={$aadsp.ID}}, @{Name="PrincipalPublisherName";Expression={$aadsp.PublisherName}}, `
                @{Name="PrincipalAppDisplayName";Expression={$aadsp.AppDisplayName}}, @{Name="PrincipalAppId";Expression={$aadsp.Appid}}, `
                @{Name="PrincipalEnabled";Expression={$aadsp.AccountEnabled}}, @{Name="ObjectType";Expression={$aadsp.ObjectType}}, `
                @{Name="ServicePrincipalType";Expression={$aadsp.ServicePrincipalType}},@{Name="CredType";Expression={"Key"}} `
                    -ExpandProperty KeyCredentials | select `
                Principal, PrincipalID, PrincipalPublisherName, PrincipalAppDisplayName, PrincipalAppId, PrincipalEnabled, `
                 ObjectType, ServicePrincipalType,CredType, displayName, type, usage, startDateTime, endDateTime
        
        @($aadApps,$aadSps) | select * -pv aadsp | select @{Name="Principal";Expression={$aadsp.displayname}}, `
                @{Name="PrincipalID";Expression={$aadsp.ID}}, @{Name="PrincipalPublisherName";Expression={$aadsp.PublisherName}}, `
                @{Name="PrincipalAppDisplayName";Expression={$aadsp.AppDisplayName}}, @{Name="PrincipalAppId";Expression={$aadsp.Appid}}, `
                @{Name="PrincipalEnabled";Expression={$aadsp.AccountEnabled}}, @{Name="ObjectType";Expression={$aadsp.ObjectType}}, `
                @{Name="ServicePrincipalType";Expression={$aadsp.ServicePrincipalType}},@{Name="CredType";Expression={"Pwd"}} `
                     -ExpandProperty PasswordCredentials | select `
                Principal, PrincipalID, PrincipalPublisherName, PrincipalAppDisplayName, PrincipalAppId, PrincipalEnabled, `
                 ObjectType, ServicePrincipalType,CredType, displayName, type, usage, startDateTime, endDateTime
}


write-host "Retrieving every Service Principal"
$sp_uri = "https://graph.microsoft.com/beta/servicePrincipals?`$expand=appRoleAssignments"
$aadsps = getFromMSGraph -uri $sp_uri | select *, @{Name="ObjectType";Expression={"ServicePrincipal"}}
write-host "Retrieving every App"
$app_uri = "https://graph.microsoft.com/beta/applications"
$aadApps = getFromMSGraph -uri $app_uri | select *, @{Name="ObjectType";Expression={"Application"}}


write-host "Building report"
exportcreds | export-csv .\aad_appcreds.csv -notypeinformation
write-host "Results found here $defaultpath"
