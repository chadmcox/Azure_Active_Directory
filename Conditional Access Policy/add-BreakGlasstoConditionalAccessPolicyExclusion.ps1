param($mgenv="Global",$BreakglassUPN)

Connect-MgGraph -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.ReadWrite.All", "Directory.AccessAsUser.All" -Environment $mgenv

if(!($BreakglassUPN)){
$BreakglassUPN = Read-Host "what is upn of the breakglass account (example: breakglass@contoso.onmicrosoft.com"
}

$bgid = (Get-MgUser -UserId $BreakglassUPN).Id

if($bgid){

Get-MgIdentityConditionalAccessPolicy -all | foreach{$policy="";$policy=$_
    write-host "Reviewing $($policy.DisplayName)"
    if($bgid -notin $policy.conditions.users.excludeUsers){
    write-host "Reviewing $($policy.DisplayName)"
$body = @"
{
    "conditions": {
        "users": {
            "excludeUsers": [
                "$(@(($policy.conditions.users.excludeUsers + $bgid) -join("`",`"")))"
            ]
        }
    }
}
"@

    Update-MgIdentityConditionalAccessPolicy -BodyParameter $body -ConditionalAccessPolicyId $policy.id
    }else{
        write-host " Found"
    }
}
}else{
write-host "cound not find breakglass account"
}
