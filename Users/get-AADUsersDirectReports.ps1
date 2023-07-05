<#
get a users direct reports and enumerates all of the others direct reports transitively

for what ever reason the function isnt working correctly I link there is suppose to be a level option i need to use.

#>

param($manager = "bob@contoso.com")
function get-userTransitiveReports{
    param($id, $manager)
    $uri = "https://graph.microsoft.com/beta/users/$($id)?`$expand=transitiveReports"
    $results = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
    $results | select -ExpandProperty transitiveReports | foreach{
        $_ | select id, displayname, userprincipalname, onPremisesSamAccountName, department, @{N="Manager";E={$manager}}
        get-userTransitiveReports -id $_.id -Manager $_.displayname
    }
}


Select-MgProfile -Name beta
$managerobj = get-mguser -UserId $manager
get-userTransitiveReports -id $managerobj.id -manager $managerobj.DisplayName | export-csv ".\$($managerobj.userprincipalname)_directreports.csv" -NoTypeInformation

