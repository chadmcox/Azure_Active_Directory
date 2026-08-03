param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Group.Read.All","Directory.Read.All"
}
cd $defaultpath

$file1 = ".\Entra_Security_Users.csv"

function GetEntraUsers {
    [cmdletbinding()]
    param()

    Write-Host "Retrieving groups...writing to this file $file2 in this directory $defaultpath"

    $uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Member'&`$select=id,displayName,OnPremisesSyncEnabled,onPremisesDomainName,createdDateTime,lastPasswordChangeDateTime,onPremisesLastSyncDateTime,refreshTokensValidFromDateTime,signInSessionsValidFromDateTime&`$top=999"

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

write-host "writing to file $file1 in directory $defaultpath"
GetEntraUsers | select id,displayName,OnPremisesSyncEnabled,onPremisesDomainName,createdDateTime,lastPasswordChangeDateTime,`
    onPremisesLastSyncDateTime,refreshTokensValidFromDateTime,signInSessionsValidFromDateTime | export-csv $file1 -NoTypeInformation

write-host "Complete"
