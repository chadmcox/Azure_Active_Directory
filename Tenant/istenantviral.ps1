<#
.SYNOPSIS
    Quick check whether a single email address belongs to a viral (unmanaged) Entra tenant.

.EXAMPLE
    .\Test-IsViralUser.ps1 -Mail john@yopmail.net

.NOTES
    Uses the unauthenticated GetUserRealm endpoint - no Graph connection required.
    Returns $true if IsViral = True on the realm response, otherwise $false.
#>

param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [string]$Mail
)

# Basic email sanity check
if ($Mail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    Write-Error "'$Mail' is not a valid email address."
    return
}

$uri = "https://login.microsoftonline.com/common/userrealm/?user=$([uri]::EscapeDataString($Mail))&api-version=2.1"

try {
    $realm = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
}
catch {
    Write-Error "GetUserRealm call failed for '$Mail': $($_.Exception.Message)"
    return
}

# Project the answer using calculated properties - no custom objects created
$realm | Select-Object `
    @{Name='Mail';            Expression={ $Mail }},
    @{Name='Domain';          Expression={ ($Mail -split '@')[1] }},
    @{Name='NameSpaceType';   Expression={ $_.NameSpaceType }},
    @{Name='FederationBrand'; Expression={ $_.FederationBrandName }},
    @{Name='CloudInstance';   Expression={ $_.CloudInstanceName }},
    @{Name='IsViral';         Expression={ [bool]($_.IsViral -eq $true -or $_.IsViral -eq 'True') }}
