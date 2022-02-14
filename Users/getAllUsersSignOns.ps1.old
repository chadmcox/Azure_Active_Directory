#requires -runasadministrator
<# This is the instructions on how to set up the application and certificate credential.
    $aad = connect-azuread
    $Global:aadName = (get-azureaddomain | ? { $_.IsDefault -eq $true }).Name
    $Global:TenantId =$aad.TenantId
    $applicationName = 'GetAllUsersLastSignOn'
    $Global:aadApp = New-AzureADApplication -DisplayName "$applicationName" -IdentifierUris ("https://" + $Global:aadName + "/" + $applicationNoSpace) -ReplyUrls "https://aad.portal.azure.com/$($Global:aadName)"
    $Global:AppId = $Global:aadApp.AppId
    $Global:aadSP = New-AzureADServicePrincipal -AppId $Global:appId
    $Global:cert = New-SelfSignedCertificate -DnsName "$applicationNoSpace.$Global:aadName" -CertStoreLocation "cert:\LocalMachine\My" -KeySpec Signature -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter (Get-Date).AddYears(1)
    $Private:KeyValue = [System.Convert]::ToBase64String($Global:cert.GetRawCertData())
    $Global:certCred = New-AzureADApplicationKeyCredential -ObjectId $Global:aadApp.ObjectId -CustomKeyIdentifier "001" -Type AsymmetricX509Cert -Usage Verify -Value $Private:KeyValue -StartDate $Global:cert.NotBefore.ToUniversalTime() -EndDate $Global:cert.NotAfter.ToUniversalTime()
    Add-AzureADDirectoryRoleMember -ObjectId (Get-AzureADDirectoryRole | ? {$_.DisplayName -eq "Directory Readers"}).Objectid -RefObjectId $Global:aadSP.ObjectId
    $roles = @(
		"AuditLog.Read.All",
		"Calendars.Read"
		"ChannelMessage.Read.All",
		"Contacts.Read",
		"Directory.Read.All",
		"Group.Read.All",
		"IdentityRiskEvent.Read.All",
		"Reports.Read.All",
		"SecurityEvents.Read.All",
        "SecurityEvents.ReadWrite.All",
		"Sites.Read.All",
		"User.Read.All"
	)
    $graph = Get-AzureADServicePrincipal -SearchString "Microsoft Graph" | ? {$_.AppId -eq '00000003-0000-0000-c000-000000000000' }
	$graphRoles = $graph.AppRoles | ? { $roles -contains $_.Value }

	$req = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
	$req.ResourceAppId = $graph.AppId
	$accesses = @()

	foreach ($role in $graphRoles)
	{
		$access = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList $role.Id,"Role"
		$accesses += $access
	}
	$req.ResourceAccess = $accesses

	Write-Host "Assigning Graph roles to AAD application"
	Set-AzureADApplication -ObjectId $Global:aadApp.ObjectId -RequiredResourceAccess $req

    Start-Sleep -Seconds 30
    $count = 0
    do
    {
        $continue = $false
        $count = $count + 1
        $authority = "https://login.microsoftonline.com/$($Global:TenantId)"
	    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
	    $cac = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate" -ArgumentList $Global:AppId, $cert
	    $task = $authContext.AcquireTokenAsync("https://graph.microsoft.com", $cac)

	    while (-not $task.IsCompleted)
	    {
		    Start-Sleep -Seconds 1
	    }
	    if ($task.Exception -ne $null)
	    {
            Write-Host "Exception message $($task.Exception.Message)"
            Write-Host "The AAD Application is not ready yet, trying again in a couple of seconds... (retry #$($count))"
            $continue = $true
            Start-Sleep -Seconds 15
        }
    }
    until (($continue -eq $false) -or ($count -eq 5))

    if ($count -gt 4)
    {
        throw [System.ApplicationException] "The application is not ready after waiting long enough, please try again later"
    }
    Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=$($Global:AppId)&state=12345&redirect_uri=https://aad.portal.azure.com/$($Global:aadName)"
    write-host "enter this into the variables inside the script"
    write-host '$Global:ApplicationId:' $Global:AppId
    write-host '$Global:Thumbprint:' $Global:cert.thumbprint
    write-host '$Global:AzureEnvironment :' $aad.Environment.Name
    write-host '$Global:TenantId:' $aad.TenantId
    write-host '$Global:TenantDomain:' $aad.TenantDomain
#>



$applicationName = 'GetAllUsersLastSignOn'
$Global:TenantId = '' #tenant guid
$Global:TenantDomain = '' #contoso.onmicrosoft.com
$Global:ApplicationId = '' #application guid
$Global:AzureEnvironment = '' #AzureCloud
$Global:Thumbprint = '' #

import-module azureadpreview
$aza = Split-Path (Get-Module AzureADPreview).Path
Add-Type -Path "$aza\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"

$resourceAppIdURI = "https://graph.microsoft.com"
$authority = "https://login.microsoftonline.com/$Global:TenantId"
$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

$cert = Get-ChildItem cert:\LocalMachine\my | ? { $_.Thumbprint -eq $Global:Thumbprint }
$cac = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate" -ArgumentList $Global:ApplicationId, $cert
$task = $authContext.AcquireTokenAsync("https://graph.microsoft.com", $cac)
$authToken = $task.Result
$requestUrl = 'https://graph.microsoft.com/beta//auditLogs/signIns?$top=1'
$authHeader = @{ 'Authorization'=$authToken.CreateAuthorizationHeader() }

Function Invoke-MSGraphQuery($AccessToken, $Uri, $Method, $Body){
    Write-Progress -Id 1 -Activity "Executing query: $Uri" -CurrentOperation "Invoking MS Graph API"
    $Header = @{
        'Content-Type'  = 'application\json'
        'Authorization' = $AccessToken.CreateAuthorizationHeader()
        }
    $QueryResults = @()
    if($Method -eq "Get"){
        do{
            $Results =  Invoke-RestMethod -Headers $Header -Uri $Uri -UseBasicParsing -Method $Method -ContentType "application/json"
            if ($Results.value -ne $null){$QueryResults += $Results.value}
            else{$QueryResults += $Results}
            write-host "Method: $Method | URI $Uri | Found:" ($QueryResults).Count
            $uri = $Results.'@odata.nextlink'
            }until ($uri -eq $null)
        }
    if($Method -eq "Post"){
        $Results =  Invoke-RestMethod -Headers $Header -Uri $Uri -Method $Method -ContentType "application/json" -Body $Body
        write-host "Method: $Method | URI $Uri | Executing"
        }
    if($Method -eq "Delete"){
        $Results =  Invoke-RestMethod -Headers $Header -Uri $Uri -Method $Method -ContentType "application/json" -Body $Body
        write-host "Method: $Method | URI $Uri | Executing"
        }
    Write-Progress -Id 1 -Activity "Executing query: $Uri" -Completed
    Return $QueryResults
}

$users_uri = "https://graph.microsoft.com/beta/users"
$Method = "Get"
$users = Invoke-MSGraphQuery -AccessToken $authToken -Uri $users_uri -Method $Method

@(foreach($user in $users){
    $objectid = $user.id
    $Uri = 'https://graph.microsoft.com/beta/auditLogs/signIns?$filter=userid eq ' + "'$objectid'"
    $Method = "Get"
    $user | select id, userPrincipalName,refreshTokensValidFromDateTime, `
    @{n='loggedinlast90days';e={if((Invoke-MSGraphQuery -AccessToken $authToken -Uri $Uri -Method $Method).value){$true}}}
}) | export-csv c:\data\signon.csv -NoTypeInformation
