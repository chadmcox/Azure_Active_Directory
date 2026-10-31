#Is PIM Configured for Azure Management Groups
Get-AzManagementGroup -pipelinevariable azmg | foreach {
    $pim = $null;$pim = Get-AzureADMSPrivilegedResource -ProviderId AzureResources -filter "externalId eq '$(($azmg).id)'"
    $azmg | select @{Name="ID";Expression={$_.id}}, @{Name="Name";Expression={$_.name}}, @{Name="Type";Expression={$_.type}}, `
    @{Name="Status";Expression={$pim.status}}, @{Name="RegisteredDateTime";Expression={$pim.RegisteredDateTime}}, `
    @{Name="RegisteredRoot";Expression={$pim.RegisteredRoot}}
 }
 
#is PIM configured for all Azure Subscriptions

Get-AzSubscription -pipelinevariable azs | foreach {
    $pim = $null;$pim = Get-AzureADMSPrivilegedResource -ProviderId AzureResources -filter "externalId eq '/subscriptions/$(($azs).id)'"
    $azs | select @{Name="ID";Expression={"/subscriptions/$($_.id)"}}, @{Name="Name";Expression={$_.name}}, @{Name="Type";Expression={"subscriptions"}}, `
    @{Name="Status";Expression={$pim.status}}, @{Name="RegisteredDateTime";Expression={$pim.RegisteredDateTime}}, `
    @{Name="RegisteredRoot";Expression={$pim.RegisteredRoot}}
 }
