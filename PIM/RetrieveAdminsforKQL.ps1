Connect-MgGraph -scope 'RoleManagement.Read.Directory','Directory.Read.All'
Select-MgProfile -Name beta
$roles = @("Application Administrator","Authentication Administrator","Cloud Application Administrator","Conditional Access Administrator","Exchange Administrator","Global Administrator","Helpdesk Administrator","Hybrid Identity Administrator","Password Administrator","Privileged Authentication Administrator","Privileged Role Administrator","Security Administrator","SharePoint Administrator","User Administrator")
(Get-MgDirectoryRole -ExpandProperty members -all | where {$_.displayname -In $roles} | select -ExpandProperty members).id  -join('","') | out-file .\privuser.txt
write-host "results found here: .\privuser.txt"
