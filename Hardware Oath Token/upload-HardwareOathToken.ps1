<#PSScriptInfo
.VERSION 2024.12
.GUID 8580e442-6a53-44cc-b821-2fe2d7fda178
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
from the use or distribution of the Sample Code..
.description
url:  How to manage hardware OATH tokens in Microsoft Entra ID (Preview) - https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens
#>

param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

cls

Start-Transcript -path $env:USERPROFILE\Downloads\transcript-newhardwaretoken.txt

Disconnect-MgGraph
#display a list of clouds for the user to select and sign-in to.
Get-MgEnvironment | select name | out-host
$selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
$mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

#this variable is used for the uri.
$graphendpoint = $mg_env.GraphEndpoint

Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All","Policy.ReadWrite.AuthenticationMethod","user.read.all" -Environment $mg_env.name

function getuserid{
    param($upn)
    $uri = "$graphendpoint/beta/users/$upn"
    $foundUser = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    return $foundUser.id
}

function uploadtoken{
    param($serialNumber,$manufacturer,$model,$secretKey,$timeIntervalInSeconds,$upn)
    $tokentoupload = @{}
    $tokentoupload.add("serialNumber","$serialNumber")
    $tokentoupload.add("manufacturer","$manufacturer")
    $tokentoupload.add("model","$model")
    $tokentoupload.add("secretKey","$secretKey")
    $tokentoupload.add("timeIntervalInSeconds","$timeIntervalInSeconds")
    if($upn){
        $UPN_hash = @{}
        $UPN_hash.add("id",(getuserid -upn $upn))
        $tokentoupload.add("assignTo",$UPN_hash)
    }
    write-host "Uploading the following token:"
    ($tokentoupload | convertto-json -Depth 99) | out-host

    $uri = "$graphendpoint/beta/directory/authenticationMethodDevices/hardwareOathDevices"
    Invoke-MgGraphRequest -Method POST -Uri $uri -ContentType "application/json" -Body ($tokentoupload | convertto-json -Depth 99)
}

if(!(get-module Microsoft.Graph.Authentication -ListAvailable)){
    write-host "Run: find-module Microsoft.Graph.Authentication | install-module"
    write-host "Then rerun the script"
    
}else{

    $selection = Read-Host "To add a single token press a and press enter or press b and press enter to bulk upload"

    if($selection -eq "b"){
        cls
        write-host "The seed file needs to be a csv."
        write-host "The following headers are required:"
        Write-host "upn,serial number,secret key,time interval,manufacturer,model"
        write-host "upn only needs to be populated if you want to assign a oath token to a user" -ForegroundColor yellow
        Read-Host "Press enter to continue if the seed file has these things" 

        $bulkuploadfile = Read-Host "Type the path of the bulk upload file and press enter (example: c:\bulk\Sample_Seed_Record_Template.csv" 

        import-csv $bulkuploadfile | foreach{
            uploadtoken -serialNumber $_."serial number" -manufacturer $_.manufacturer -model $_.model -secretKey $_."secret key" -timeIntervalInSeconds $_."time interval" -upn $_.upn
        }

    }else{
        $input_serialNumber = $null; $input_serialNumber = Read-Host "Type the Serial Number, then press enter"
        $input_manufacturer = $null; $input_manufacturer = Read-Host "Type the Manufacturer, then press enter"
        $input_model = $null; $input_model = Read-Host "Type the Model, then press enter"
        $input_secretKey = $null; $input_secretKey = Read-Host "Type the Secret Key, then press enter"
        $input_timeIntervalInSeconds = $null; $input_timeIntervalInSeconds = Read-Host "Type the timeIntervalInSeconds, then press enter"
        $input_upn = $null; $input_upn = Read-Host "Type the upn if you want to assign, if not leave blank, then press enter"

        uploadtoken -serialNumber $input_serialNumber -manufacturer $input_manufacturer -model $input_model -secretKey $input_secretKey -timeIntervalInSeconds $input_timeIntervalInSeconds -upn $input_upn
    }
}

Stop-Transcript
write-host "Transcripts can be found here $env:USERPROFILE\Downloads\transcript-newhardwaretoken.txt"
