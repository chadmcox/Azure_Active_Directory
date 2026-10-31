<#PSScriptInfo
.VERSION 2026.10
.GUID 18bf582a-f85b-4a89-8f60-e52845ca1c08
.AUTHOR Chad Cox
    https://blogs.technet.microsoft.com/chadcox/
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
.description
Flattens every Conditional Access policy into one CSV row with a column for every setting, by walking each policy object, so new policy settings show up without code changes.
url: List policies - https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-beta
#>
<#
.SYNOPSIS
    Exports every Conditional Access policy setting to CSV.
.DESCRIPTION
    Replaces exportConditionalAccessPolicytoCSV. Scalar arrays are joined into one cell; arrays of
    objects get an index, like conditions.locations[1].
.PARAMETER Delimiter
    Separator used when joining array values. Default "; ".
.EXAMPLE
    .\Export-CAPoliciesToCsv.ps1 -Environment Global
#>
[CmdletBinding()]
param(
    [ValidateSet("Global", "USGov", "USGovDoD")][string]$Environment,
    [string]$Delimiter = "; ",
    [string]$Path = "$env:USERPROFILE\Downloads"
)

function Connect-Cloud {
    param([string[]]$Scopes, [switch]$Identity)
    $clouds = "Global", "USGov", "USGovDoD"
    if (-not $script:Environment) {
        Get-MgEnvironment | Where-Object { $_.Name -in $clouds } | Select-Object Name, GraphEndpoint | Out-Host
        $answer = Read-Host "Type the cloud to connect to (Global, USGov, USGovDoD). Press Enter for Global"
        $script:Environment = if ($answer -in $clouds) { $answer } else { "Global" }
    }
    if ($Identity) {
        Connect-MgGraph -Identity -Environment $script:Environment -NoWelcome
    } else {
        Connect-MgGraph -Scopes $Scopes -Environment $script:Environment -NoWelcome
    }
    $script:Graph = "$((Get-MgEnvironment -Name $script:Environment).GraphEndpoint)/beta"
}

function Get-Policies {
    $uri = "$script:Graph/identity/conditionalAccess/policies"
    do {
        $response = Invoke-MgGraphRequest -Uri $uri -OutputType Hashtable -ErrorAction Stop
        $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)
}

# Walks any hashtable, array or value and fills an ordered dictionary of dotted path -> value.
function ConvertTo-FlatMap {
    param($InputObject, [string]$Prefix = "", [System.Collections.Specialized.OrderedDictionary]$Result = ([ordered]@{}))
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ($key -like "@odata*") { continue }
            $childPath = if ($Prefix) { "$Prefix.$key" } else { [string]$key }
            ConvertTo-FlatMap $InputObject[$key] $childPath $Result | Out-Null
        }
    } elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = @($InputObject)
        $nested = $items | Where-Object { $_ -is [System.Collections.IDictionary] }
        if (-not $items.Count) { $Result[$Prefix] = $null }
        elseif (-not $nested) { $Result[$Prefix] = $items -join $Delimiter }
        else { for ($i = 0; $i -lt $items.Count; $i++) { ConvertTo-FlatMap $items[$i] "$Prefix[$i]" $Result | Out-Null } }
    } elseif ($Prefix) {
        $Result[$Prefix] = $InputObject
    }
    $Result
}

# Identity columns first, then every other column sorted.
function Get-ColumnOrder {
    param($Maps)
    $lead = "displayName", "state", "id", "createdDateTime", "modifiedDateTime", "description"
    $keys = $Maps | ForEach-Object { $_.Keys } | Select-Object -Unique
    $lead | Where-Object { $_ -in $keys }
    $keys | Where-Object { $_ -notin $lead } | Sort-Object
}

# One calculated property per column. GetNewClosure pins the key for each column.
function Get-ColumnDefinition {
    param([string[]]$Columns)
    foreach ($column in $Columns) {
        $key = $column
        @{ n = $key; e = { $_[$key] }.GetNewClosure() }
    }
}

Connect-Cloud -Scopes "Policy.Read.All"

$maps = @(Get-Policies | ForEach-Object { ConvertTo-FlatMap $_ })
# Export-Csv builds the header from the first row, so every row gets the union of all columns.
$properties = @(Get-ColumnDefinition -Columns @(Get-ColumnOrder -Maps $maps))
$file = Join-Path $Path "conditional_access_policies_$(Get-Date -Format yyyyMMdd-HHmm).csv"
$maps | ForEach-Object { Select-Object -InputObject $_ -Property $properties } | Export-Csv $file -NoTypeInformation -Encoding UTF8
Write-Host "$($maps.Count) policies, $($properties.Count) columns. Results: $file"
