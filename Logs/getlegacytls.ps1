#https://gist.github.com/merill/379c76c3fa4b6c003207ede4f9a5406d

cd $env:USERPROFILE
#!!!!! update with the aadtenant id !!!!!!!
$TenantId = "1316e071-fbe0-4de5-b131-c5f8ac5850bb"
connect-mggraph -scopes "Directory.Read.All", "AuditLog.Read.All" -TenantId $TenantId
$agoDays = 5 #will filter the log for $agoDays from current date/time
$startDate = (Get-Date).AddDays(-($agoDays)).ToString('yyyy-MM-dd')

function list-frommsgraph{
    [cmdletbinding()]
    param($uri)
do{
            $results = $null
            $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
            $results.value 
            $uri=$null;$uri = $Results.'@odata.nextlink'
        }until (($uri -eq $null))
}

$uri = "https://graph.microsoft.com/beta/auditLogs/signins?`$filter=createdDateTime ge $startDate"
list-frommsgraph -uri $uri | Foreach-Object {
    foreach ($authDetail in $_.AuthenticationProcessingDetails)
    {
        if(($authDetail.Key -match "Legacy TLS") -and ($authDetail.Value -eq "True")){
            $_ | select CorrelationId, createdDateTime, userPrincipalName, userId, UserDisplayName, AppDisplayName, AppId, IPAddress, isInteractive, ResourceDisplayName, ResourceId 
        }
    }

} | Export-Csv -NoTypeInformation -Path ".\Interactive_lowTls_$tId.csv"
