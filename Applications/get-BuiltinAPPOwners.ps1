#this script will look at all the built-in apps and call out if they have a owner.
#https://dirkjanm.io/azure-ad-privilege-escalation-application-admin/
#want the ability to prevent the assignment of credentials and grant role assignment
param($defaultpath = "$env:USERPROFILE\Downloads")
if(!(Get-MgContext)){
    connect-mggraph -scopes "Application.Read.All","Directory.Read.All"
}
cd $defaultpath
Get-MgBetaServicePrincipal -all -ExpandProperty owners | `
    where {$_.PublisherName -like "*Microsoft*" -or !($_.PublisherName -eq "Microsoft Accounts") -and $_.AppOwnerOrganizationId -eq 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'} | `
        where {$_.owners -like "*"} | select appid, displayname,PublisherName, owners
