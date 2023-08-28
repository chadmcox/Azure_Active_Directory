Get-MgBetaUser -Filter "userType eq 'Guest'" -ExpandProperty ownedObjects -all | `
    select userprincipalname, ownedObjects | where {$_.ownedObjects -like "*"} | foreach{
        $guest=$null;$guest=$_
       $_ | select userprincipalname -ExpandProperty ownedObjects | `
        select @{N="userprincipalname";E={$guest.UserPrincipalName}}, `
            @{N="ownedObjects";E={$_.id}}
    }
