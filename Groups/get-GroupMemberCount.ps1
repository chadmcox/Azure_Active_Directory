param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\member_count_groups.csv"

function GetAADGroupCounts {
    [cmdletbinding()]
    param()

    Write-Host "Retrieving groups...writing to this file $file1 in this directory $defaultpath"

    $uri = "https://graph.microsoft.com/beta/groups?`$select=id,displayName,groupTypes,OnPremisesSyncEnabled,mailEnabled,SecurityEnabled,onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier&`$top=999"

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

        $results.value |
            Select-Object displayName,
                          id,
                          OnPremisesSyncEnabled,mailEnabled, SecurityEnabled,
                          @{N="DynamicGroup";E={$_.groupTypes -contains "DynamicMembership"}},
                          @{N="MemberCount";E={

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
                          }},onPremisesDomainName, onPremisesLastSyncDateTime,createdDateTime,isAssignableToRole,onPremisesSecurityIdentifier

        $uri = $results.'@odata.nextLink'

    } until ($null -eq $uri)
}

GetAADGroupCounts | export-csv $file1 -notypeinformation

Write-Host "Complete"
