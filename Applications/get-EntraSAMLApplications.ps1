param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

Get-MgBetaServicePrincipal -filter "preferredSingleSignOnMode eq 'saml'" -all -ExpandProperty owners| select `
    Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\entra_saml_apps.csv -NoTypeInformation
