#this will list all Windows devices
get-azureaddevice -all $true | where DeviceOSType -like "Windows*" | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_windows.csv -NoTypeInformation

#this will list all worplace joined devices. Ideal not to have personal devices unless their is a byod stratagy
get-azureaddevice -Filter "DeviceTrustType eq 'Workplace'" -all $true | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_workplacejoined.csv -NoTypeInformation
        
get-azureaddevice -Filter "DeviceTrustType eq 'Workplace'" -all $true | where DeviceOSType -like "Windows*" | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_windows_workplacejoined.csv -NoTypeInformation

#this will list all hybrid joined devices 
get-azureaddevice -Filter "DeviceTrustType eq 'ServerAD'" -all $true | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_hybridjoined.csv -NoTypeInformation

#this will list all direct azure ad joined devices
get-azureaddevice -Filter "DeviceTrustType eq 'AzureAD'" -all $true | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_aadjoined.csv -NoTypeInformation

#list all stale devices
$dt = [datetime]'2020/01/01'
get-azureaddevice -all $true | where {$_.ApproximateLastLogonTimeStamp -le $dt} | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_stale.csv -NoTypeInformation
        
#disable stale accounts
$dt = [datetime]'2020/01/01'
get-azureaddevice -all $true | where {$_.ApproximateLastLogonTimeStamp -le $dt} | set-azureaddevice -accountenabled $false

#list disabled devices
get-azureaddevice -all $true | where {$_.AccountEnabled -eq $false} | select `
    objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_disabled.csv -NoTypeInformation
        
#Delete stale disabled computers
$dt = [datetime]'2020/01/01'
get-azureaddevice -all $true | where {$_.ApproximateLastLogonTimeStamp -le $dt -and $_.AccountEnabled -eq $false} | Remove-AzureADDevice

#list Hybrid Joined Computers no longer syncing and havent been logged into since a specific date.
$dt = [datetime]'2020/03/01'
get-azureaddevice -Filter "DeviceTrustType eq 'ServerAD'" -all $true | where {$_.DirSyncEnabled -ne $true -and $_.ApproximateLastLogonTimeStamp -lt $dt} | 
    select objectid, deviceid, DisplayName,AccountEnabled,ApproximateLastLogonTimeStamp,DeviceOSType,DeviceOSVersion, `
        DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ProfileType | export-csv .\aad_device_serverad_brokesync.csv -NoTypeInformation

#this will list devices that are still being used but are disabled
Get-AzureADAuditSignInLogs -filter "appDisplayName eq 'Microsoft Office' and status/errorCode eq 135011" -all $true | select `
    UserPrincipalName,AppDisplayName, @{Name="DeviceName";Expression={$_.DeviceDetail.DisplayName}}, `
    @{Name="ErrorCode";Expression={$_.Status.errorcode}}, @{Name="FailureReason";Expression={$_.Status.FailureReason}} -Unique | `
        export-csv .\aad_device_still_used_but_disabled.csv

#using MSOL module - list devices hybrid device joined in pending state 
#https://docs.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-manual#using-powershell
Get-MsolDevice -All -IncludeSystemManagedDevices | `
  where {($_.DeviceTrustType -eq 'Domain Joined') -and (-not([string]($_.AlternativeSecurityIds)).StartsWith("X509:"))} | select `
    objectid, deviceid, displayname, enabled, DeviceOSVersion, DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ApproximateLastLogonTimeStamp | `
        export-csv .\aad_device_pendinghybridjoin.csv -NoTypeInformation
    
#using MSOL module - Get Stale Devices
Get-MsolDevice -All -LogonTimeBefore 'January 1, 2020 12:00:00 AM' | select `
    objectid, deviceid, displayname, enabled, DeviceOSVersion, DeviceTrustType,DirSyncEnabled,LastDirSyncTime,ApproximateLastLogonTimeStamp | `
        export-csv .\aad_device_stale.csv -NoTypeInformation

#using msol module - Disable Stale Devices
Get-MsolDevice -All -LogonTimeBefore 'January 1, 2020 12:00:00 AM' | disable-msoldevice -force

#Using MSOL Module - Remove Disabled stale objects Objects
Get-MsolDevice -All -LogonTimeBefore 'January 1, 2020 12:00:00 AM' | where enabled -ne $true | Remove-MsolDevice -force
