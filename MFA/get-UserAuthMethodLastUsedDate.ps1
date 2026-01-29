param($resultslocation = "$env:USERPROFILE\Downloads")

cd $resultslocation

Connect-MgGraph -Scopes "Directory.Read.All","User.Read.All","UserAuthenticationMethod.Read.All"
cd $resultslocation

$users = Get-MgBetaUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all | select id, DisplayName

$users | foreach{ $u=$null;$u=$_
    Get-MgBetaUserAuthenticationMethod -UserId $u.Id | foreach{$authm=$null;$authm=$_
    $authm | select -ExpandProperty AdditionalProperties | convertto-json -Depth 99 | Convertfrom-Json | where {!($_."@odata.type" -eq '#microsoft.graph.passwordAuthenticationMethod')}  | select `
       @{N="UserId";E={$u.id}}, `
       @{N="UserDisplayName";E={$u.DisplayName}}, `
       @{N="AuthMethodLastUsedDate";E={$authm.LastUsedDateTime}}, `
       @{N="AuthMethodType";E={$_."@odata.type"}}, `
       displayName,phoneNumber
    }
} | export-csv $resultslocation\EntraUserAuthMethods.csv

Write-host "Results found here $resultslocation\EntraUserAuthMethods.csv"
