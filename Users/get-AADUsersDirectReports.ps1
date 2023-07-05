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
$manager = "bob@contoso.com"
$managerobj = get-mguser -UserId $manager
get-userTransitiveReports -id $managerobj.id -manager $managerobj.DisplayName | export-csv ".\$($managerobj.userprincipalname)_directreports.csv" -NoTypeInformation

