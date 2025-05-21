#script can be used to query the audit log and populate the sponsor information on the guest account.
connect-mggraph -Scopes User.ReadWrite.All, Directory.ReadWrite.All,AuditLog.Read.All,Directory.Read.All

function getAADGuestInvite{
    [cmdletbinding()] 
    param()
    write-host "Exporting all Guest to: $resultslocation, this may take a while"
    $uri = "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Invite external user'"
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

$all_guest_invites = getAADGuestinvite


foreach($event in $all_guest_invites){
$uri = "https://graph.microsoft.com/beta/users/$($event.targetResources.id)/sponsors/`$ref"
$body = @"
{
  "@odata.id": "https://graph.microsoft.com/beta/users/$($event.initiatedBy.user.id)"
}
"@
Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body
}
