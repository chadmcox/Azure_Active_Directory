<#PSScriptInfo
.VERSION 2024.19
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
https://learn.microsoft.com/en-us/graph/api/resources/hardwareoathtokenauthenticationmethoddevice?view=graph-rest-beta
#>

param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

cls

Start-Transcript -path .\transcript-activatehardwaretoken.txt

Disconnect-MgGraph
#display a list of clouds for the user to select and sign-in to.
Get-MgEnvironment | select name | out-host
$selection = Read-Host "Type the name of the azure environment that you would like to connect to:  (example Global)"
if($selection -notin "Global","China","USGov","Germany","USGovDoD"){$selection = "Global"}
$mg_env = Get-MgEnvironment | where {$_.name -eq $selection}

#this variable is used for the uri.
$graphendpoint = $mg_env.GraphEndpoint

Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All","Policy.ReadWrite.AuthenticationMethod","Directory.Read.All","User.ReadBasic.All" -Environment $mg_env.name

function getuserid{
    param($upn)
    $uri = "$graphendpoint/beta/users/$upn"
    $foundUser = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    return $foundUser.id
}

function getuserhardwareoathtokens{
    param($userid)
    $uri = "$graphendpoint/beta/users/$userid/authentication/hardwareOathMethods"
    $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    foreach($oathtoken in $results.value.id){
        $uri = "$graphendpoint/beta/directory/authenticationMethodDevices/hardwareOathDevices/$oathtoken"
        $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
        $results | out-host
    }
}

Function activateUserHardwareOathToken{
    param($userid, $oathtokenid, $vcode)
    $verificationcode = @{}
    $verificationcode.add("verificationCode","$vcode")
    $uri = "$graphendpoint/beta/users/$userid/authentication/hardwareOathMethods/$oathtokenid/activate"
    Invoke-MgGraphRequest -Method POST -Uri $uri -ContentType "application/json" -Body ($verificationcode | convertto-json -Depth 99)
    start-sleep -Seconds 3
    getuserhardwareoathtokens -userid $userid
    write-host "Validate hardware token $oathtokenid has been activated"
}


cls

$input_upn=$null;$input_upn = Read-Host "Type the UPN of the user"


$user_id=$null;$user_id = getuserid -upn $input_upn

cls

getuserhardwareoathtokens -userid $user_id

$input_token_id_to_activate = Read-Host "Scroll up, then copy the id of the token you want to activate and paste here, then press enter"
$input_verification_code = Read-Host "Enter the code from the hardware token, then press enter"
cls
activateUserHardwareOathToken -userid $user_id -oathtokenid $input_token_id_to_activate -vcode $input_verification_code

Stop-Transcript
