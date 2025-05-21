<#
.VERSION 2022.4.19
.GUID 18bf582a-f85b-4a87-8f60-e52845ca1c08
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
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
from the use or distribution of the Sample Code..
.DESCRIPTION
This script retrieves a list of policies from my github and gives the user the option to enter them into the tenant.
#>

Get-MgEnvironment | select name | out-host
$selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
$mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

$graphendpoint = $mg_env.GraphEndpoint


$exit = $false
function add-AADCAP{
    [CmdletBinding()]
    param($objnewcap)
    write-host "Importing $($objnewcap.displayname)"
    if($objnewcap.displayname -eq "Report Only - All Users - Block Tor Exit Nodes"){
        $locations = @(add-TorExitNodes)
        write-host "adding tor exit not locations to policy"
        $objnewcap.conditions.locations.includeLocations = $locations
    }
    try{Invoke-MgGraphRequest -Method POST -uri "$graphendpoint/v1.0/identity/conditionalAccess/policies" `
            -ContentType "application/json" -Body ($objnewcap | convertto-json -Depth 99)}
        catch{$_
        Write-host "Error"}
}
function add-TorExitNodes{
    write-host "importing tor exit node list"
    #retrieve trusted location
    $body = (invoke-webrequest -uri "https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/JSON/Tor_Exit_Notes.json").content | convertfrom-json
    $results = Invoke-MgGraphRequest -Method POST -Uri "$graphendpoint/v1.0/identity/conditionalAccess/namedLocations" -Body ($body | convertto-json -Depth 99)
    return $results.id
}

$policy = $null
#retrieve the list fromt he cloud
$caps = ((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional%20Access%20Policy/JSON/recommended_conditional_access_policies.json").content  | convertfrom-json).value | `
    select displayName, state, sessionControls, conditions, grantControls

Connect-MgGraph -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.ReadWrite.All", "Directory.AccessAsUser.All" -Environment $mg_env.name
Select-MgProfile -Name beta
do{

    if($caps){
        cls
        write-host "---Menu: Which Conditional Access policy would you like to Import-------"
        Write-host ""
        $menu_option = 0
        foreach($cap in $caps){
            write-host "$menu_option - $($cap.displayname)"
            $menu_option++
        }
        Write-host "$menu_option - To Import All Policies" -ForegroundColor Yellow
        Write-host ""
        write-host "-----------------------------------------------------------------------"
        Write-host ""
        $selection = Read-Host "Type 0 - $menu_option to import to conditional access policy or type 'exit' to exit"

        if($selection -eq "exit"){
            write-host "exit"
            $exit = $true
        }elseif($selection -eq $menu_option){
            write-host "Importing All"
            foreach($cap in $caps){
                $policy = "";$policy=$cap
                $policy.displayName = "Report Only - $($policy.displayName)"
                add-AADCAP -objnewcap $policy
            }
        }else{
    
            $policy = "";$policy = $caps[$selection]
            $policy.displayName = "Report Only - $($policy.displayName)"
            add-AADCAP -objnewcap $policy
        }
    }else{
     write-host "Unable to retrive list of Conditional access policies from https://raw.githubusercontent.com/chadmcox/Azure_Active_Directory/master/Conditional Access Policy/JSON/recommended_conditional_access_policies.json"

    }
    Write-host "Finished Importing, Make sure to add breakglass exclusions"
    pause
}until($exit -eq $true)


