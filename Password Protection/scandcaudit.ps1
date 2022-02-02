#https://docs.microsoft.com/en-us/azure/active-directory/authentication/howto-password-ban-bad-on-premises-monitor#dc-agent-admin-event-log

Get-ADForest | select -ExpandProperty domains -pv domain | foreach{
    Get-ADDomainController -filter * -server $domain -pv dc | foreach{
        write-host "Scanning DC: $($dc.hostname) in domain: $domain"
        Get-WinEvent -FilterHashtable @{LogName="Microsoft-AzureADPasswordProtection-DCAgent/Admin";ID=10024,10025,30008,30007,30010,30009,30028,30029,30024,30023} -ComputerName $dc.hostname -pv event | foreach{
            $_.properties[0] | select @{N="Domain";E={$domain}}, @{N="User";E={$_.value}}, `
            @{N="EventID";E={if($event.id -eq 30008){"$($event.id) Password Change Audit-only Pass (would have failed customer password policy)"}
            elseif($event.id -eq 30007){"$($event.id) Password Set Audit-only Pass (would have failed customer password policy)"}
            elseif($event.id -eq 30010){"$($event.id) Password Change Audit-only Pass (would have failed Microsoft password policy)"}
            elseif($event.id -eq 30009){"$($event.id) Password Set Audit-only Pass (would have failed Microsoft password policy)"}
            elseif($event.id -eq 30028){"$($event.id) Password Change Audit-only Pass (would have failed combined Microsoft and customer password policies)"}
            elseif($event.id -eq 30029){"$($event.id) Password Set Audit-only Pass (would have failed combined Microsoft and customer password policies)"}
            elseif($event.id -eq 30024){"$($event.id) Password Change Audit-only Pass (would have failed due to user name)"}
            elseif($event.id -eq 30023){"$($event.id) Password Set Audit-only Pass (would have failed due to user name)"}
            else{$event.id}}}
        }
    }
}  | export-csv "$env:USERPROFILE\found_10025.csv" -notypeinformation
