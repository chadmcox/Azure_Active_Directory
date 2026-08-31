<#
.VERSION 2023.4.18
.GUID 18bf582a-f85b-4a89-8f60-e52845ca1c08
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/ (retired)
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
from the use or distribution of the Sample Code..
.DESCRIPTION
This script is unique.  almost all code requires to know the mapping.  what makes this different is I crawl
the object and each properties sub object.  this way as conditional access policy change.  this will change along with it.

This code is a hack job but works perfectly.  I appologies for not using good variables or function names.

4/22 i have it using the location command to translate its guid
it was trying to enum the sign in frecuency I fixed that

#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $env:USERPROFILE "Downloads\CAPolicies-$(Get-Date -f yyyyMMdd-HHmm).csv"),
    [ValidateSet('v1.0', 'beta')][string]$ApiVersion = 'v1.0',
    [string]$Delimiter = '; '
)

# Walks any hashtable/array/scalar graph and fills an ordered dictionary of
# dotted path -> scalar. Scalar arrays join into one cell; object arrays index,
# so conditions.locations[1].* appears without any code change.
function ConvertTo-FlatMap {
    param(
        $InputObject,
        [string]$Prefix = '',
        [System.Collections.Specialized.OrderedDictionary]$Result = ([ordered]@{})
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ($key -like '@odata*') { continue }
            $path = if ($Prefix) { "$Prefix.$key" } else { [string]$key }
            ConvertTo-FlatMap $InputObject[$key] $path $Result | Out-Null
        }
    }
    elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = @($InputObject)
        $nested = $items | Where-Object { $_ -is [System.Collections.IDictionary] }

        if (-not $items.Count) { $Result[$Prefix] = $null }
        elseif (-not $nested)  { $Result[$Prefix] = $items -join $Delimiter }
        else { for ($i = 0; $i -lt $items.Count; $i++) { ConvertTo-FlatMap $items[$i] "$Prefix[$i]" $Result | Out-Null } }
    }
    elseif ($Prefix) {
        $Result[$Prefix] = $InputObject
    }

    $Result
}

# Streams column order: identity fields first, then everything else sorted.
function Get-ColumnOrder {
    param($Maps)

    $lead = 'displayName', 'state', 'id', 'createdDateTime', 'modifiedDateTime', 'description'
    $keys = & { foreach ($map in $Maps) { $map.Keys } } | Select-Object -Unique

    $lead | Where-Object { $_ -in $keys }
    $keys | Where-Object { $_ -notin $lead } | Sort-Object
}

# One calculated property per column. GetNewClosure pins the key per iteration.
function Get-ColumnDefinition {
    param([string[]]$Columns)

    foreach ($column in $Columns) {
        $key = $column
        @{ Name = $key; Expression = { $_[$key] }.GetNewClosure() }
    }
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
if (-not (Get-MgContext)) { Connect-MgGraph -Scopes Policy.Read.All | Out-Null }

$maps = @(
    (Invoke-MgGraphRequest -Uri "/$ApiVersion/identity/conditionalAccess/policies" -OutputType Json |
        ConvertFrom-Json -AsHashtable -Depth 100).value |
        ForEach-Object { ConvertTo-FlatMap $_ }
)

# Header must be the union of ALL policies' keys - Export-Csv builds it from the
# first object only, so a policy without session controls would drop those
# columns for every other policy in the file.
$properties = @(Get-ColumnDefinition -Columns @(Get-ColumnOrder -Maps $maps))

$(foreach ($map in $maps) { Select-Object -InputObject $map -Property $properties }) |
    Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

Write-Host "$($maps.Count) policies, $($properties.Count) columns -> $Path" -ForegroundColor Green


write-host "Results found here: $path" -ForegroundColor Yellow
