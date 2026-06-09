# Requires: Microsoft.Graph.Beta
# Scopes:   User.Read.All, Group.Read.All, Directory.Read.All, Application.Read.All

connect-mggraph -scopes  User.Read.All, Group.Read.All, Directory.Read.All, Application.Read.All

# Reusable calculated-property blocks (script blocks captured for reuse)
$domainExpr = { (($_ -replace '^[a-zA-Z0-9]+:','') -split '@' | Select-Object -Last 1).Trim() }

# ---------- USERS (active) ----------
$users = Get-MgBetaUser -All -Property `
    UserPrincipalName,Mail,OtherMails,ProxyAddresses,OnPremisesUserPrincipalName |
ForEach-Object {
    $id = $_.UserPrincipalName

    # UserPrincipalName row
    $_.UserPrincipalName | Select-Object `
        @{N='ObjectType';E={'User'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'UserPrincipalName'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    # Mail row
    $_.Mail | Select-Object `
        @{N='ObjectType';E={'User'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'Mail'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    # OnPremisesUserPrincipalName row (shadow UPN)
    $_.OnPremisesUserPrincipalName | Select-Object `
        @{N='ObjectType';E={'User'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'OnPremisesUserPrincipalName'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    # OtherMails — one row per entry
    $_.OtherMails | Select-Object `
        @{N='ObjectType';E={'User'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'OtherMails'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    # ProxyAddresses — one row per entry
    $_.ProxyAddresses | Select-Object `
        @{N='ObjectType';E={'User'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'ProxyAddress'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- USERS (soft-deleted) ----------
$deletedUsers = Get-MgBetaDirectoryDeletedItemAsUser -All -Property `
    UserPrincipalName,Mail,OtherMails,ProxyAddresses |
ForEach-Object {
    $id = $_.UserPrincipalName

    $_.UserPrincipalName | Select-Object `
        @{N='ObjectType';E={'DeletedUser'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'UserPrincipalName'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    $_.Mail | Select-Object `
        @{N='ObjectType';E={'DeletedUser'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'Mail'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    $_.OtherMails | Select-Object `
        @{N='ObjectType';E={'DeletedUser'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'OtherMails'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    $_.ProxyAddresses | Select-Object `
        @{N='ObjectType';E={'DeletedUser'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'ProxyAddress'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- GROUPS ----------
$groups = Get-MgBetaGroup -All -Property DisplayName,Mail,ProxyAddresses |
ForEach-Object {
    $id = $_.DisplayName

    $_.Mail | Select-Object `
        @{N='ObjectType';E={'Group'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'Mail'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    $_.ProxyAddresses | Select-Object `
        @{N='ObjectType';E={'Group'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'ProxyAddress'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- ORG CONTACTS ----------
$contacts = Get-MgBetaContact -All -Property DisplayName,Mail,ProxyAddresses |
ForEach-Object {
    $id = $_.DisplayName

    $_.Mail | Select-Object `
        @{N='ObjectType';E={'OrgContact'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'Mail'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}

    $_.ProxyAddresses | Select-Object `
        @{N='ObjectType';E={'OrgContact'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'ProxyAddress'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- APP REGISTRATIONS ----------
$apps = Get-MgBetaApplication -All -Property DisplayName,IdentifierUris |
ForEach-Object {
    $id = $_.DisplayName
    $_.IdentifierUris | Select-Object `
        @{N='ObjectType';E={'Application'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'IdentifierUri'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- SERVICE PRINCIPALS ----------
$sps = Get-MgBetaServicePrincipal -All -Property DisplayName,ServicePrincipalNames |
ForEach-Object {
    $id = $_.DisplayName
    $_.ServicePrincipalNames | Select-Object `
        @{N='ObjectType';E={'ServicePrincipal'}},
        @{N='Identifier';E={$id}},
        @{N='Attribute';E={'SPN'}},
        @{N='Value';E={$_}},
        @{N='Domain';E=$domainExpr}
}

# ---------- EXPORT ----------
$users + $deletedUsers + $groups + $contacts + $apps + $sps |
    Where-Object { $_.Value -and $_.Domain } |
    Sort-Object Domain, ObjectType, Identifier, Attribute |
    Export-Csv .\EntraDomainReferences.csv -NoTypeInformation -Encoding UTF8
