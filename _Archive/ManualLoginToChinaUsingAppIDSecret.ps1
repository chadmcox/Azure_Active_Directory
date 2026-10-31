# using appid and secret
$appid = ''
$tenantid = ''
$secret = ''
 
$body =  @{
    Grant_Type    = "client_credentials"
    Scope         = "https://microsoftgraph.chinacloudapi.cn/.default"
    Client_Id     = $appid
    Client_Secret = $secret
}
 
$connection = Invoke-RestMethod `
    -Uri "https://login.partner.microsoftonline.cn/$tenantid/oauth2/v2.0/token" `
    -Method POST `
    -Body $body

$authHeader = @{
      "Authorization" = "Bearer " + $connection.access_token
    }

#the authheader can then be passed to

$uri = "https://microsoftgraph.chinacloudapi.cn/beta/users"
$results = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get -ContentType "application/json"
