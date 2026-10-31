Connect-AzAccount -Environment AzureChinaCloud
$accessToken = (Get-AzAccessToken -ResourceUrl "https://microsoftgraph.chinacloudapi.cn").Token
$authHeader = @{
      "Authorization" = "Bearer " + $AccessToken
    }
    
$uri = "https://microsoftgraph.chinacloudapi.cn/beta/users"
$results = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get -ContentType "application/json"
