connect-mggraph -scope "Policy.Read.All","Policy.ReadWrite.ConditionalAccess"
$url = "https://raw.githubusercontent.com/SecOps-Institute/Tor-IP-Addresses/master/tor-exit-nodes.lst"
$response = Invoke-WebRequest $url -UseBasicParsing
$ipRegex = "\b(?:\d{1,3}\.){3}\d{1,3}\b"
$ipAddresses = $response.Content | Select-String -Pattern $ipRegex -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }

$count = $ipAddresses.count
$counter = 0; $title = 1
while ($counter -lt $count)
{
  $body = @{
            "@odata.type" = "#microsoft.graph.ipNamedLocation"
            displayName = "Untrusted IP named location IPv4"
            ipRanges = New-Object System.Collections.ArrayList # Use list to always conver to json properly
            IsTrusted = $false
        }  
    for ($i=0; $i -lt 1000; $i++)
    { 
      if($counter -lt $count){
      $body.ipRanges.add(@{
                    "@odata.type" = "#microsoft.graph.iPv4CidrRange"
                    cidrAddress = "$($ipAddresses[$counter])/32"
                })
        $counter++
        }
    }
    $title++
    if($body.ipRanges){
    New-MgBetaIdentityConditionalAccessNamedLocation -BodyParameter ($body |convertto-json)
    }
}
