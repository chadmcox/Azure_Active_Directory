param($defaultdirectory="$env:USERPROFILE\Downloads")
cd $defaultdirectory

connect-mggraph -scope 'Application.Read.All', 'Directory.Read.All', 'AuditLog.Read.All'

# desktop apps
Get-MgBetaServicePrincipal  -all -ExpandProperty owners | where {$_.ReplyUrls -contains "urn:ietf:wg:oauth:2.0:oob"} | `
 where {!($_.PublisherName -like "*Microsoft*") -or $_.PublisherName -eq "Microsoft Accounts" -and !($_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a')-and $_.appDisplayname -ne "Microsoft Assessments"} | select `
    Id, AppId, DisplayName,PublisherName,AccountEnabled, AppRoleAssignmentRequired, preferredSingleSignOnMode, `
    signInAudience, @{N="createdDateTime";E={[datetime]$_.AdditionalProperties.createdDateTime}}, `
    @{N="ReplyUrls";E={[string]$($_.ReplyUrls)}}, @{N="tags";E={[string]$($_ | select -expandproperty tags)}}, `
    @{N="NotificationEmailAddresses";E={[string]$_.NotificationEmailAddresses}}, `
    @{N="Owner";E={($_.owners.id | foreach{Get-MgBetaDirectoryObjectById -ids $_  | select -ExpandProperty AdditionalProperties | ConvertTo-Json | convertfrom-json}).DisplayName -join(";")}} | `
        export-csv .\entra_desktop_apps.csv -NoTypeInformation
