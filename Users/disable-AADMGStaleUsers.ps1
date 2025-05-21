param($defaultpath="$env:USERPROFILE\downloads",$staleindays = 480,$removalthreshold = 250)
cd $defaultpath
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Directory.AccessAsUser.All","User.Read.All","AuditLog.Read.All"
Select-MgProfile -Name beta

write-host "this will disable the first $removalthreshold stale users"

Get-MgUser -Filter "userType eq 'Member' and AccountEnabled eq true" -all  -Property id, displayName, signInActivity, userPrincipalName, userType, `
    onPremisesSyncEnabled, createdDateTime, accountEnabled, passwordPolicies, mail, lastPasswordChangeDateTime | `
        where {($_.signInActivity.LastSignInDateTime -eq $null)  -or `
            ((New-TimeSpan -Start $_.signInActivity.LastSignInDateTime -end $(get-date)).TotalDays -gt $staleindays)} | `
        where {($_.signInActivity.LastNonInteractiveSignInDateTime -eq $null) -or `
            ((New-TimeSpan -Start $_.signInActivity.LastNonInteractiveSignInDateTime -end $(get-date)).TotalDays -gt $staleindays)} | `
        where {(New-TimeSpan -Start $_.lastPasswordChangeDateTime -end $(get-date)).TotalDays -gt $staleindays} | select * -first $removalthreshold | foreach {
          write-host "Disabling $($_.userPrincipalName)"
            Update-MgUser -UserId $_.id -AccountEnabled:$false
        }
