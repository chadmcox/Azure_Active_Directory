param($resultslocation = "$env:USERPROFILE\Downloads")

cd $resultslocation

Connect-MgGraph -Scopes "Policy.Read.All","Reports.Read.All","AuditLog.Read.All","Directory.Read.All","Directory.Read.All","User.Read.All","AuditLog.Read.All"
cd $resultslocation
function getAADUserMFAStatus{
    [cmdletbinding()] 
    param()
    $uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails"
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
                }
            }
        }
        $results.value
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}



$results = getAADUserMFAStatus  | where {$_.userprincipalname -like "*EXT*"}
$results | select id,userPrincipalName,userDisplayName, isRegistered, isEnabled, isCapable,isMfaRegistered, @{N="authMethods";E={[string]$_.authMethods}} `
    | export-csv .\AAD_Guest_MFA_Status.csv -NoTypeInformation
$results | where {$_.isMFARegistered -eq $true}  -PipelineVariable st | select -ExpandProperty authMethods | `
    select @{N="userPrincipalName";E={$st.userPrincipalName}},@{N="authMethods";E={$_}} | export-csv .\AAD_Guest_Registered_AuthMethods.csv -NoTypeInformation

write-host "Results found here $resultslocation"
