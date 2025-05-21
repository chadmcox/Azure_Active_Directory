<#PSScriptInfo

.VERSION 2022.8.03

.GUID 1be4febf-db79-4b83-9e81-ab88b4dda0c8

.AUTHOR Chad.Cox@microsoft.com
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

.TAGS Get-AzureRmContext Set-AzureRmContext Get-AzureRmRoleAssignment get-msoluser

.DESCRIPTION 
 This script is going to create a relationship csv for all of the management groups and subscriptions

#> 
Param($path="$env:userprofile\downloads")
write-host "Need to connect to Azure and Azure AD"
Connect-AzAccount
Connect-AzureAD

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

function expandAzMG{
    [cmdletbinding()]
    param($name)
    write-information "Expanding Azure Manageent Group $name"
    Get-AzManagementGroup -GroupName $name -Expand -pv mg | select -ExpandProperty Children | foreach{
        $_ | select @{N="Parent";E={$mg.displayname}},@{N="Parentid";E={$mg.id}},@{N="Child";E={$_.displayname}},@{N="Childid";E={$_.id}},@{N="ChildType";E={$_.type}}
        if($_.type -eq "/providers/Microsoft.Management/managementGroups"){
            expandAzMG -name $_.name
        }
    }
}
function drawazrelationships{
    Param($Parent, $hl, $vl, [switch]$notroot)
    $parent.text
    if($hash_subcount.ContainsKey("$($Parent.text)")){
                    $childsub = $page.Drop($SUB, ($hl - 0.5), $vl)
                    $childsub.Text = "Subscription Count $($hash_subcount["$($parent.text)"].total)"
                    $parent.Autoconnect($childsub, 0)
                    $vl -= 1.5
                }
    if($hash_relationships.containskey($parent.text)){
        $hash_relationships["$($parent.text)"] | foreach{
            if($_.childtype -eq "/providers/Microsoft.Management/managementGroups"){
                $child = $page.Drop($MG, $hl, $vl)
                $child.Text = $_.child
                $parent.Autoconnect($child, 0)
                
                drawazrelationships -Parent $child -hl ($hl + 1.5)  -vl ($vl) -notroot
                if($notroot -eq $false){
                    $vl -= 1.5
                    }
                if($hash_mgrelationships.containskey($child.text)){
                    $vl -= (1.5 * ($hash_relationships[$_.child]).count)
                    
                }else{
                    $vl -= 1.5
                }
            <#}elseif($_.childtype -eq "/subscriptions"){
                
                $child = $page.Drop($SUB, $hl, $vl)
                $child.Text = $_.child
                $parent.Autoconnect($child, 0)
                #drawazrelationships -Parent $child -hl ($hl)  -vl ($vl - 5)
                
                #$vl -= 1
            }#>
        }
    }
}
}

$Visio = New-Object -ComObject Visio.Application
$Doc=$Visio.Documents.Add('')
$Page=$Visio.ActivePage

$pages = $Visio.ActiveDocument.Pages


$stencil = $Visio.Documents.Add("AZUREGENERAL_U.vssx")
$MG = $stencil.Masters.Item("Management Groups")
$SUB = $stencil.Masters.Item("Subscriptions")

$shape = $page.Drop($MG, 0.5, 10)
$shape.Text = "Tenant Root Group"

write-host "Exporting All Management groups"
expandAzMG -name (Get-AzureADTenantDetail).objectid | export-csv "$path\az_parent_child_relationships.csv" -notypeinformation

write-host "Building visio"

$hash_relationships = import-csv "$path\az_parent_child_relationships.csv" |  where {$_.childtype -eq "/providers/Microsoft.Management/managementGroups"} | group parent -AsHashTable -AsString

$hash_mgrelationships = import-csv "$path\az_parent_child_relationships.csv" | where {$_.childtype -eq "/providers/Microsoft.Management/managementGroups"} | group parent -AsHashTable -AsString

$hash_subcount = import-csv "$path\az_parent_child_relationships.csv" | where {$_.childtype -eq "/subscriptions"} | group parent | select name, @{N="Total";E={$_.count}} | group name -AsHashTable -AsString

drawazrelationships -Parent $shape -hl 2 -vl 9

write-host "Results found here $path"
