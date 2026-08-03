Connect-MgGraph -Scopes "Group.Read.All","Directory.Read.All"

function GetAADDynamicGroups {
    [cmdletbinding()]
    param()

    Write-Host "Retrieving dynamic groups..."

    $uri = "https://graph.microsoft.com/beta/groups?`$select=id,displayName,groupTypes,membershipRule,membershipRuleProcessingState&`$top=999"

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
            Where-Object { $_.groupTypes -contains "DynamicMembership" } |
            Select-Object displayName,
                          id,
                          membershipRuleProcessingState,
                          membershipRule

        $uri = $results.'@odata.nextLink'

    } until ($null -eq $uri)
}

GetAADDynamicGroups | where {$_.membershipRule -match "memberOf"}
