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

param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
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

function returnSPDelegatedPerms{
    [cmdletbinding()]
        param()

    $hash_approles = $aadsps | select id, displayname | group id -AsHashTable -AsString

    foreach($aadsp in $aadsps){
        write-host "$($aadsp.displayname)"
        $spra_uri = "https://graph.microsoft.com/beta/servicePrincipals/$($aadsp.id)/oauth2PermissionGrants"
        getFromMSGraph -uri $spra_uri -pv oauth2 | Foreach{
            $_.scope -split(" ") | select `
            @{Name="Principal";Expression={$aadsp.displayname}}, `
            @{Name="PrincipalID";Expression={$aadsp.ID}}, `
            @{Name="PrincipalPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="PrincipalAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="PrincipalAppId";Expression={$aadsp.Appid}}, `
            @{Name="PrincipalEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="ServicePrincipalType";Expression={$aadsp.ServicePrincipalType}}, `
            @{Name="Scope";Expression={$_}}, `
            @{Name="API";Expression={$hash_approles[$oauth2.resourceId].displayname}}, `
            @{Name="Consenttype";Expression={$oauth2.consentType}}
        } 
    }
}

write-host "Retrieving every Service Principal"
$sp_uri = "https://graph.microsoft.com/beta/servicePrincipals?`$filter=servicePrincipalType eq 'Application'"
$aadsps = getFromMSGraph -uri $sp_uri
write-host "Building Report"
returnSPDelegatedPerms | select Principal,PrincipalID,PrincipalPublisherName,PrincipalAppDisplayName,PrincipalAppId, `
    PrincipalEnabled,ServicePrincipalType,Scope,API,Consenttype -Unique | export-csv .\aad_appoauth2perms.csv -NoTypeInformation

write-host "Results found here $defaultpath"
