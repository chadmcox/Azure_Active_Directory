<#PSScriptInfo
.VERSION 2021.10
.GUID 368f7248-347a-46d9-ba35-3ae42890daed
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/
    https://github.com/chadmcox
.COMPANYNAME
.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample 
.Note
because the azuread modules do not handle time outs this script can be incomplete
#>

Connect-MgGraph -Scopes "CrossTenantInformation.ReadBasic.All","AuditLog.Read.All","Directory.Read.All"

cd "$env:USERPROFILE\Downloads"
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
                }else{
                    write-host "Error: $($_.Exception.response.statuscode)"
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

$querydate=$(get-date (get-date).AddDays(-10) -Format yyyy-MM-dd)
$hash_alreadyfound = @{}
$tenantid = (Get-MgContext).TenantId
$uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=ResourceTenantId ne '$tenantid' and appDisplayName ne 'Microsoft Teams Web Client' and status/errorCode eq 0 and createdDateTime gt $querydate"
getFromMSGraph -uri $uri | where {$_.appDisplayName -notlike "*sharepoint*"} | select ResourceTenantId, appDisplayName -pv event -First 10000 | foreach{
    if(!($hash_alreadyfound.ContainsKey($($event.ResourceTenantId)))){
    $hash_alreadyfound.Add($($event.ResourceTenantId),$true)
    $uri_t = "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$($event.ResourceTenantId)')"
    getFromMSGraph -uri $uri_t
    }
} | select tenantId, displayName, defaultDomainName, @{Name="appDisplayName";Expression={$event.appDisplayName}} | export-csv .\azuread_resource_tenants.csv -NoTypeInformation

write-host "file can be found here $env:USERPROFILE\Downloads" 
