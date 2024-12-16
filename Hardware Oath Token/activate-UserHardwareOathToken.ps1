
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

Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All","Policy.ReadWrite.AuthenticationMethod","Directory.Read.All","User.ReadBasic.All" -Environment $mg_env.name

function getuserid{
    param($upn)
    $uri = "$graphendpoint/beta/users/$upn"
    $foundUser = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    return $foundUser.id
}

function getuserhardwareoathtokens{
    param($userid)
    $uri = "$graphendpoint/beta/users/8f7859a3-3739-4b9c-a248-5e049b46e45a/authentication/hardwareOathMethods"
    $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    foreach($oathtoken in $results.value.id){
        $uri = "$graphendpoint/beta/directory/authenticationMethodDevices/hardwareOathDevices/$oathtoken"
        $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
        $results | out-host
    }
}
cls

$input_upn=$null;$input_upn = Read-Host "Type the UPN of the user"


$user_id=$null;$user_id = getuserid -upn $input_upn

cls

getuserhardwareoathtokens -userid $user_id

$input_token_id_to_activate = Read-Host "Scroll up find the token you want to activate, then copy the id and paste here, then press enter"
