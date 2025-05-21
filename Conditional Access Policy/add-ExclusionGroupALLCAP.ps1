Connect-MgGraph -Scopes "Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Directory.ReadWrite.All", "Directory.AccessAsUser.All", "GroupMember.ReadWrite.All","Group.ReadWrite.All"

#update this to meet requirements
$groupprefix = "GRP.CAP.Exclude"

#Create Admin Unit

$body = @"
{
    "displayName": "AU.CAP.Exclusion - Conditional Access Policy Exclusion Groups",
    "description": "Conditional Access Policy Exclusion Groups for administration",
    "visibility": "HiddenMembership"
}
"@

$au = Invoke-MgGraphRequest -Method POST -uri "https://graph.microsoft.com/beta/administrativeUnits" -ContentType 'application/json' -body $body
$AllPolicies = (Invoke-MgGraphRequest -Method GET -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -OutputType PSObject).value

#Create groups for each policy, link to admin unit and update cap
#will need to run rest of this code together.

foreach($p in $AllPolicies){
$body = @"
{
  "@odata.type": "#Microsoft.Graph.Group",
  "description": "Group to Exclude Conditional Access Policy: $($p.displayname)",
  "displayName": "$groupprefix - $($p.displayname)",
  "groupTypes": [
  ],
  "mailEnabled": false,
  "mailNickname": "capExclude$(1..10000 | get-random)",
  "securityEnabled": true,
}
"@

$grp = Invoke-MgGraphRequest -Method POST -uri "https://graph.microsoft.com/beta/administrativeUnits/$($au.id)/members" -ContentType 'application/json' -body $body

#add to conditional access policy
$addtoexc = @(($p.conditions.users.excludeGroups + $($grp.id)) -join("`",`""))

$body = @"
{
    "conditions": {
        "users": {
            "excludeGroups": [
                "$addtoexc"
            ]
        }
    }
}
"@

$uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($p.id)"
Invoke-MgGraphRequest -Uri $Uri -Method PATCH -ContentType "application/json" -body $body

}
