#https://docs.microsoft.com/en-us/azure/active-directory/authentication/howto-password-ban-bad-on-premises-monitor#dc-agent-admin-event-log

Get-ADForest | select -ExpandProperty domains -pv domain | foreach{
    Get-ADDomainController -filter * -server $domain -pv dc | foreach{
        write-host "Scanning DC: $($dc.hostname) in domain: $domain"
        Get-WinEvent -FilterHashtable @{LogName="Microsoft-AzureADPasswordProtection-DCAgent/Admin";ID=30002,30003,30004,30005,30026,30008,30027,30007,30010,30009,30028,30029,30024,30023} -ComputerName $dc.hostname -pv event | foreach{
            $_.properties[0] | select @{N="Domain";E={$domain}}, @{N="User";E={$_.value}}, `
            @{N="EventID";E={if($event.id -eq 30008){"$($event.id) Password Change Audit-only Pass (would have failed customer password policy)"}
            elseif($event.id -eq 30007){"$($event.id) Password Set Audit-only Pass (would have failed customer password policy)"}
            elseif($event.id -eq 30010){"$($event.id) Password Change Audit-only Pass (would have failed Microsoft password policy)"}
            elseif($event.id -eq 30009){"$($event.id) Password Set Audit-only Pass (would have failed Microsoft password policy)"}
            elseif($event.id -eq 30028){"$($event.id) Password Change Audit-only Pass (would have failed combined Microsoft and customer password policies)"}
            elseif($event.id -eq 30029){"$($event.id) Password Set Audit-only Pass (would have failed combined Microsoft and customer password policies)"}
            elseif($event.id -eq 30024){"$($event.id) Password Change Audit-only Pass (would have failed due to user name)"}
            elseif($event.id -eq 30023){"$($event.id) Password Set Audit-only Pass (would have failed due to user name)"}
            elseif($event.id -eq 30002){"$($event.id) Password Change Fail (due to customer password policy)"}
            elseif($event.id -eq 30003){"$($event.id) Password Set Fail (due to customer password policy)"}
            elseif($event.id -eq 30005){"$($event.id) Password Set Fail (due to Microsoft password policy)"}
            elseif($event.id -eq 300026){"$($event.id) Password Change Fail (due to combined Microsoft and customer password policies)"}
            elseif($event.id -eq 300027){"$($event.id) Password Set Fail (due to combined Microsoft and customer password policies)"}
            elseif($event.id -eq 30004){"$($event.id) Password Change Fail (due to Microsoft password policy)"}
            else{$event.id}}}
        }
    }
}  | export-csv "$env:USERPROFILE\password_protection_results.csv" -notypeinformation
