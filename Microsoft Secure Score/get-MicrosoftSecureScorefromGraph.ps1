
param($resultslocation = "$env:USERPROFILE\Downloads",$filename="Microsoft Secure Score - Microsoft Defender Test.csv")
cd $resultslocation
if(get-module Microsoft.Graph.Beta.Security,Microsoft.Graph.Security -listavailable){
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

Write-host "Retrieving Microsoft Secure Score Profiles"
#this created a lookup hash table used to fill in the blanks
#this particular cmdlet returns things just fine
if(get-command Get-MgBetaSecuritySecureScoreControlProfile){
$ssprofiles = Get-MgBetaSecuritySecureScoreControlProfile -All | select * -Unique | group id -AsHashTable -AsString
}else{
$ssprofiles = Get-MgSecuritySecureScoreControlProfile -All | select * -Unique | group id -AsHashTable -AsString
}

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

function return-securescore{
    [cmdletbinding()]
    param()
    #the cmdlet seems to timeout.  I have better luck sending this directly to graph.
    #$securescore = Get-MgBetaSecuritySecureScore -Top 1

    $uri = "$graphendpoint/beta/security/secureScores?`$top=1"
    $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject

    $ssresults = $results.value.controlScores

    $possibleMaxScore = $results.value.maxScore
    foreach($ss in $ssresults){ 
            $ss | where {$ssprofiles[$ss.controlName].Title} | select  `
            @{N="Rank";E={"$($ssprofiles[$ss.controlName].rank)"}}, `
            @{N="Recommended action";E={"$($ssprofiles[$ss.controlName].Title)"}}, `
            @{N="Score impact";E={"$("{0:P2}" -f ([int]$ssprofiles[$ss.controlName].maxscore / [int]$possibleMaxScore))"}}, `
            @{N="Points achieved";E={"$($ss.score) / $($ssprofiles[$ss.controlName].maxscore)"}}, `
            @{N="Status";E={if($ss.score -ge $ssprofiles[$ss.controlName].maxscore){"Completed"}else{"To address"}}}, `
            @{N="Regress";E={"NA"}}, `
            @{N="Have license?";E={"NA"}}, `
            @{N="Category";E={"$($ss.ControlCategory)"}}, `
            @{N="Product";E={decipher-ssproduct -product $ssprofiles[$ss.controlName].service}}, `
            @{N="Last synced";E={"$($ss.lastSynced)"}}
    }
}
Write-host "Retrieving Microsoft Secure Score"
return-securescore | export-csv ".\$filename" -NoTypeInformation
write-host "Complete, File can be found here: $resultslocation\$filename"
}else{
    write-host "Not able to find required module: Microsoft.Graph.Beta.Security or Microsoft.Graph.Security"
}
