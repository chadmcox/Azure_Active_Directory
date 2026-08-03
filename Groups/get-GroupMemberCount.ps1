param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\Entra_Security_Groups_Member_Count.csv"
$file2 = ".\Entra_Security_Groups.csv"

function GetEntraGroups {
    [cmdletbinding()]
    param()

    Write-Host "Retrieving groups...writing to this file $file2 in this directory $defaultpath"

    $uri = "https://graph.microsoft.com/beta/groups?`$filter=securityEnabled eq true and mailEnabled eq false&`$select=id,displayName,groupTypes,OnPremisesSyncEnabled,mailEnabled,SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier&`$top=999"

    do {
        $results = $null

        for($i = 0; $i -le 3; $i++) {
            try {
                $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
                break
            }
            catch {
                if(($_.Exception.Response.StatusCode -eq "TooManyRequests") -or
                   ($_.Exception.Response.StatusCode.value__ -eq 429)) {

                    Write-Host "Error: $($_.Exception.Response.StatusCode), retrying $($i + 1) of 3"
                    Start-Sleep -Seconds $_.Exception.Response.Headers.RetryAfter.Delta.Seconds
                }
                else {
                    Write-Host $_.Exception.Message
                    break
                }
            }
        }

        $results.value

        $uri = $results.'@odata.nextLink'

    } until ($null -eq $uri)
}

function getentragroupcount {
    [cmdletbinding()]
    param($groupid)
    $countUri = "https://graph.microsoft.com/beta/groups/$($_.id)/members/`$count"
    $count    = -1

    for($x = 0; $x -le 3; $x++) {
        try {
            $count = Invoke-MgGraphRequest -Uri $countUri -Method GET -Headers @{ConsistencyLevel="eventual"}
            break
        }
        catch {
            if(($_.Exception.Response.StatusCode -eq "TooManyRequests") -or
                ($_.Exception.Response.StatusCode.value__ -eq 429)) {

                Start-Sleep -Seconds $_.Exception.Response.Headers.RetryAfter.Delta.Seconds
            }
            else {
                Write-Host $_.Exception.Message
                break
            }
        }
    }

    [int]$count          
}


$groups = GetEntraGroups
$groups | Select-Object displayName,id,OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,@{N="DynamicGroup";E={$_.groupTypes -contains "DynamicMembership"}}, `
                onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier| export-csv $file2 -NoTypeInformation
Write-Host "Retrieved $($Groups.Count) groups"
Write-Host "Now Retrieving group member count writing to $file1"
$groups | Select-Object displayName,id,OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,@{N="DynamicGroup";E={$_.groupTypes -contains "DynamicMembership"}}, `
                @{N="MemberCount";E={getentragroupcount -groupid $($_.id)}},onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier | export-csv $file1 -notypeinformation

Write-Host "Complete"
