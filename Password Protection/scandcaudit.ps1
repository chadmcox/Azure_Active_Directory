#https://docs.microsoft.com/en-us/azure/active-directory/authentication/howto-password-ban-bad-on-premises-monitor#dc-agent-admin-event-log

Get-ADForest | select -ExpandProperty domains -pv domain | foreach{
    Get-ADDomainController -filter * -server $domain -pv dc | foreach{
        write-host "Scanning DC: $($dc.hostname) in domain: $domain"
        Get-WinEvent -FilterHashtable @{LogName="Microsoft-AzureADPasswordProtection-DCAgent/Admin";ID=10025,10024} -ComputerName $dc.hostname -pv event | foreach{
            $_.properties[0] | select @{N="Domain";E={$domain}}, @{N="User";E={$_.value}}, @{N="EventID";E={$event.id}}
        }
    }
}  | export-csv "$env:USERPROFILE\found_10025.csv" -notypeinformation
