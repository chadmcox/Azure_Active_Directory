
param($resultslocation = "$env:USERPROFILE\Downloads",$filename="Microsoft Secure Score - Microsoft Defender Test.csv")
cd $resultslocation
if(get-module Microsoft.Graph.Authentication -listavailable){
#I find when admins have access to multiple environments it is best to start this with a disconnect just in case.
Disconnect-MgGraph

#display a list of clouds for the user to select and sign-in to.
Get-MgEnvironment | select name | out-host
$selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
$mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

#this variable is used for the uri.
$graphendpoint = $mg_env.GraphEndpoint

Connect-MgGraph -Scopes SecurityEvents.Read.All -Environment $mg_env.name

Function decipher-ssproduct{
    [cmdletbinding()]
    param($product)
    #this makes the products readable.  Unfortunatly for the ones I do not know will just show a generic service code.
    switch ($product) {
        "Admincenter" {return "Microsoft Admin Center"}
        "Azure ATP" {return "Defender for Identity"}
        "AzureAD" {return "Microsoft Entra ID"}
        "EXO" {return "Exchange Online"}
        "FORMS" {return "Microsoft Forms"}
        "Intune" {return "Intune"}
        "MCAS" {return "Microsoft Defender for Cloud Apps"}
        "MDATP" {return "Defender for Endpoint"}
        "MDO" {return "Defender for Office"}
        "MIP" {return "Microsoft Information Protection"}
        "MS Teams" {return "Microsoft Teams"}
        "SPO" {return "SharePoint Online"}
        "SWAY" {return "Microsoft Sway"}
        default {return $product}
    }
}

function get-secureScoreControlProfilesbyservice{
    [cmdletbinding()] 
    param()
    #This thing times out and struggles to get all the profiles regularly.
    #in order to make this work better I am trying to narrow the data that gets returned
    "Admincenter","Azure ATP","AzureAD","EXO","Intune","MCAS","MDATP","MDO","MIP","MS Teams","SPO" | foreach{
        write-host "retrieving secure score profile where service is $($_)"
        $uri = "$graphendpoint/v1.0/security/secureScoreControlProfiles?`$filter=service eq '$($_)'"
        do{$results = $null
            Start-Sleep -Seconds 10
            for($i=0; $i -le 3; $i++){
                try{
                    Start-Sleep -Seconds 1
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
}
function get-secureScoreControlProfilesbycontrolCategory{
    [cmdletbinding()] 
    param()
    #This thing times out and struggles to get all the profiles regularly.
    #in order to make this work better I am trying to narrow the data that gets returned
    "Identity","Data","Device","Apps","Infrastructure" | foreach{
        Start-Sleep -Seconds 10
        write-host "retrieving secure score profile where controlCategory is $($_)"
        $uri = "$graphendpoint/v1.0/security/secureScoreControlProfiles?`$filter=controlCategory eq '$($_)'"
        do{$results = $null
            for($i=0; $i -le 3; $i++){
                try{
                    Start-Sleep -Seconds 1
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
}

function return-securescore{
    [cmdletbinding()]
    param()
    #the cmdlet seems to timeout.  I have better luck sending this directly to graph.
    #$securescore = Get-MgBetaSecuritySecureScore -Top 1
    do{$results=$null
        Start-Sleep -Seconds 10
        $uri = "$graphendpoint/v1.0/security/secureScores?`$top=1"
        $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    }until($results.value)
    $ssresults = $results.value.controlScores
    write-host "Total secureScores: $($ssresults.count)"
    $possibleMaxScore = $results.value.maxScore
    foreach($ss in $ssresults){
        if($ssprofiles[$ss.controlName].Title){
            $ss | where {$ssprofiles[$ss.controlName].Title} | select  `
                @{N="Rank";E={"$($ssprofiles[$ss.controlName].rank)"}}, `
                @{N="Recommended action";E={"$($ssprofiles[$ss.controlName].Title)"}}, `
                @{N="Score impact";E={"$("{0:P2}" -f ([int]$ssprofiles[$ss.controlName].maxscore / [int]$possibleMaxScore))"}}, `
                @{N="Points achieved";E={"$($ss.score) out of $($ssprofiles[$ss.controlName].maxscore)"}}, `
                @{N="Status";E={if($ss.score -ge $ssprofiles[$ss.controlName].maxscore){"Completed"}else{"To address"}}}, `
                @{N="Regress";E={"NA"}}, `
                @{N="Have license?";E={"NA"}}, `
                @{N="Category";E={"$($ss.ControlCategory)"}}, `
                @{N="Product";E={decipher-ssproduct -product $ssprofiles[$ss.controlName].service}}, `
                @{N="Last synced";E={"$($ss.lastSynced)"}}
        }else{
            write-host "Not found in cache searching graph for controlName: $($ss.controlName)"
            Start-Sleep -Seconds 1
            $uri = "$graphendpoint/v1.0/security/secureScoreControlProfiles/$($ss.controlName)"
            try{Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject | select  `
                @{N="Rank";E={"$($_.rank)"}}, `
                @{N="Recommended action";E={"$($_.Title)"}}, `
                @{N="Score impact";E={"$("{0:P2}" -f ([int]$_.maxscore / [int]$possibleMaxScore))"}}, `
                @{N="Points achieved";E={"$($ss.score) out of $($_.maxscore)"}}, `
                @{N="Status";E={if($ss.score -ge $_.maxscore){"Completed"}else{"To address"}}}, `
                @{N="Regress";E={"NA"}}, `
                @{N="Have license?";E={"NA"}}, `
                @{N="Category";E={"$($ss.ControlCategory)"}}, `
                @{N="Product";E={decipher-ssproduct -product $_.service}}, `
                @{N="Last synced";E={"$($ss.lastSynced)"}}}catch{}
        }
    }
}

Write-host "Retrieving Microsoft Secure Score Profiles"
#this created a lookup hash table used to fill in the blanks
#this particular cmdlet returns things but sometimes not everything
$ssprofiles = $null
$tmpssprofiles = (get-secureScoreControlProfilesbyservice) + (get-secureScoreControlProfilesbycontrolCategory)
write-host "Total secureScoreControlProfiles: $($tmpssprofiles.count)"
$ssprofiles = $tmpssprofiles | select * -unique | group id -AsHashTable -AsString



Write-host "Retrieving Microsoft Secure Score"
return-securescore | export-csv ".\$filename" -NoTypeInformation
write-host "Complete, File can be found here: $resultslocation\$filename"
}else{
    write-host "Not able to find required module: Microsoft.Graph.Authentication"
}
