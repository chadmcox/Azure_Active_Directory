<#PSScriptInfo
.VERSION 2021.10
.GUID 368f7248-347a-46d9-ba35-3ae42890daed
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/
    https://github.com/chadmcox
.COMPANYNAME
.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample 

.Note
because the azuread modules do not handle time outs this script can be incomplete

#>
cd "$env:USERPROFILE\Downloads"

function createcredhash{
    [cmdletbinding()]
        param()
        $allApps | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDate)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDate
            $_.PasswordCredentials | where {(get-date ($_.EndDate)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDate
        }
        $allSPs  | foreach{$appid = $_.appid
            $_.KeyCredentials | where {(get-date ($_.EndDate)) -gt (get-date).datetime} | select @{Name="appId";Expression={$appid}},EndDate
            $_.PasswordCredentials | where {(get-date ($_.EndDate)) -gt (get-date).DateTime} | select @{Name="appId";Expression={$appid}},EndDate
        }
}

function returnSPDelegatedPerms{
    [cmdletbinding()]
        param()

    $hash_approles = $allSPs | where {!($_.approles.AllowedMemberTypes -like "*user*")} | `
            select AppDisplayName -ExpandProperty AppRoles | group id -AsHashTable -AsString

    foreach($aadsp in $allSPs){
        write-host "Exporting app perms for: $($aadsp.displayname)"
        Get-AzureADServiceAppRoleAssignedTo -objectid $aadsp.objectid -All $tru | foreach{
            $hash_approles[$_.Id] | select `
            @{Name="Scope";Expression={$_.value}}, `
            @{Name="API";Expression={$_.AppDisplayName}}, `
            @{Name="Description";Expression={$_.Description -replace "`n|`r"," " }}, `
            @{Name="Principal";Expression={$aadsp.displayname}}, `
            @{Name="PrincipalID";Expression={$aadsp.objectid}}, `
            @{Name="PrincipalPublisherName";Expression={$aadsp.PublisherName}}, `
            @{Name="PrincipalAppDisplayName";Expression={$aadsp.AppDisplayName}}, `
            @{Name="PrincipalAppId";Expression={$aadsp.Appid}}, `
            @{Name="SevicePrincipalType";Expression={$aadsp.ServicePrincipalType}}, `
            @{Name="PrincipalEnabled";Expression={$aadsp.AccountEnabled}}, `
            @{Name="hasValidCred";Expression={$cred_hash.containskey($aadsp.Appid)}}
        }
    }
}
function returnAppCredentials{
    [cmdletbinding()]
        param()
        @($allSPs,$allApps) | foreach{
            write-host "Exporting Credentials for: $($_.displayname)"
            $_ | select @{Name="Principal";Expression={$_.displayname}},@{Name="SevicePrincipalType";Expression={$_.ServicePrincipalType}},`
            @{Name="ServicePrincipalEnabled";Expression={$_.AccountEnabled}} `
                 -expandproperty KeyCredentials | select Principal, SevicePrincipalType, Type, Usage, StartDate, EndDate
            $_ | select @{Name="Principal";Expression={$_.displayname}},@{Name="SevicePrincipalType";Expression={$_.ServicePrincipalType}}, `
                @{Name="ServicePrincipalEnabled";Expression={$_.AccountEnabled}} `
                -expandproperty PasswordCredentials | select Principal, SevicePrincipalType, Type, Usage, StartDate, EndDate
        }
}

write-host "Gathering Apps and SPs from Azure AD"
$allSPs = Get-azureadServicePrincipal -all $true
$allApps = Get-azureadApplication -all $true
write-host "Building credential hash table"
$cred_hash = createcredhash | group appid -AsHashTable -AsString
returnSPDelegatedPerms | export-csv .\appperms.csv -NoTypeInformation
returnAppCredentials | where {$_.SevicePrincipalType -ne 'ManagedIdentity' -and $_.Usage -ne "Sign"} | export-csv .\appcreds.csv -NoTypeInformation

clr
write-host "Finished: Two files are created here $("$env:USERPROFILE\Downloads")"
