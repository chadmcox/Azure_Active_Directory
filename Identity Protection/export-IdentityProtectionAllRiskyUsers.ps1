#Requires -module Microsoft.Graph.Authentication
<#
.GUID 18c37c40-e24d-4524-8c78-607d6969cb6e
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
    https://github.com/chadmcox
.Disclaimer
Use at your own risk

.Description
This script is going to create a report to view current risky users.

Once research consider using the link to the other script to flush out older risky users
https://github.com/chadmcox/Azure_Active_Directory_Scripts/blob/master/Identity%20Protection/dismissMGAIPRiskyUsers.ps1
#>
param($resultslocation = "$env:USERPROFILE\Downloads")

Connect-MgGraph -Scopes "Policy.Read.All","Reports.Read.All","AuditLog.Read.All","Directory.Read.All","Directory.Read.All","User.Read.All","AuditLog.Read.All","IdentityRiskyUser.Read.All","IdentityRiskEvent.Read.All"
cd $resultslocation

function getAADRiskyUsers{
    [cmdletbinding()] 
    param()
    write-host "Exporting all riskyusers to: $resultslocation, this may take a while"
$uri = "https://graph.microsoft.com/beta/riskyUsers?`$filter=riskState eq 'atRisk'"
    do{$results = $null
        for($i=0; $i -le 3; $i++){
            Start-Sleep -Seconds 2
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


getAADRiskyUsers | export-csv .\azuread_riskyusers.csv -notypeinformation

write-host "Results can be found here: $resultslocation"
