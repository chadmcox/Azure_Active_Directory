#Requires -module Microsoft.Graph.Authentication
<#
.GUID 18c37c40-e24d-4534-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk

.Description
This script will go out and pull results about mfa status

#>
param($resultslocation = "$env:USERPROFILE\Downloads")

cd $resultslocation

Connect-MgGraph -Scopes "Policy.Read.All","Reports.Read.All","AuditLog.Read.All","Directory.Read.All","Directory.Read.All","User.Read.All","AuditLog.Read.All"
cd $resultslocation
function getAADUserMFAStatus{
    [cmdletbinding()] 
    param()
    $uri = "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails"
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



$results = getAADUserMFAStatus | where {$_.isMfaRegistered -eq $true -and $_.userType -eq 'member'}
$results | select id,userPrincipalName,userDisplayName,userType,isAdmin, isMfaRegistered,isPasswordlessCapable,defaultMfaMethod,userPreferredMethodForSecondaryAuthentication, @{N="methodsRegistered";E={[string]$_.methodsRegistered}} `
    | export-csv .\AAD_User_MFA_Status.csv -NoTypeInformation
write-host "Results found here $resultslocation"
