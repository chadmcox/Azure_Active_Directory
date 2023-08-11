function queryGraph{
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
                }
            }
        }
        if($results.value){
            $results.value
        }else{
            $results
        }
        $uri=$null;$uri = $Results.'@odata.nextlink'
    }until ($uri -eq $null)
}

expandGroup{
    [cmdletbinding()] 
    param($id)

}


$uri = 'https://graph.microsoft.com/beta/deviceManagement/roleDefinitions'
$role_permissions = queryGraph -uri $uri -pv action | `
    select -ExpandProperty permissions rolePermissions | select -ExpandProperty actions | select `
    @{N="displayName";E={$action.displayname}}, `
    @{N="Permission";E={$_}} | group displayname -AsHashTable -AsString


$uri = "https://graph.microsoft.com/beta/deviceManagement/roleAssignments"
$role_members = queryGraph -uri $uri -pv role | foreach{
    $role | select displayName -expandproperty scopeMembers | select `
        @{N="displayName";E={$role.displayname}}, `
        @{N="Member";E={$_}},@{N="Type";E={"scopeMembers"}}
    $role | select displayName -expandproperty members | select `
        @{N="displayName";E={$role.displayname}}, `
        @{N="Member";E={$_}},@{N="Type";E={"members"}}
} | select displayName, Member, type -Unique

$role_members | foreach{$role=$null;$role = $_
    Get-MgBetaGroup -groupId $($role.Member) | select `
       @{N="roleDisplayName";E={$role.displayname}}, `
       @{N="Type";E={$role.type}}, `
       @{N="Member";E={$_.displayname}}, `
       @{N="Membertype";E={"#microsoft.graph.group"}}, `
       @{N="Permission";E={($role_permissions[$role.displayname].Permission) -join(";")}}
    Get-MgBetaGroupMember -groupId $($role.Member) -all | select  -ExpandProperty AdditionalProperties | `
        foreach{ $_ | convertto-json | convertfrom-json | select `
       @{N="roleDisplayName";E={$role.displayname}}, `
       @{N="Type";E={$role.type}}, `
       @{N="Member";E={$_.displayname}}, `
       @{N="Membertype";E={$_."@odata.type"}}, `
       @{N="Permission";E={($role_permissions[$role.displayname].Permission) -join(";")}}
}} | Out-GridView
