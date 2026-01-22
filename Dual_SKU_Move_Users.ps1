param(
    [string]$DatabasePath = ".\GroupMembers.sqlite"
)

# --- HARDCODE YOUR GROUP IDs HERE ---
$GroupIds = @(
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",  # Group 1 ID
    "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # Group 2 ID
)  # Edit these Object IDs [web:55]

# --- Modules ---
Import-Module PSSQLite
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"  # [web:55]

# Ensure DB
if (-not (Test-Path $DatabasePath)) {
    New-Item -ItemType File -Path $DatabasePath -Force | Out-Null
}

# Create table
$queryCreate = @"
CREATE TABLE IF NOT EXISTS GroupMembers (
    Id        INTEGER PRIMARY KEY AUTOINCREMENT,
    UPN       TEXT NOT NULL,
    EA1       TEXT NULL,
    DateAdded TEXT NOT NULL
);
"@
Invoke-SqliteQuery -DataSource $DatabasePath -Query $queryCreate  # [web:16]

$insertSql = @"
INSERT INTO GroupMembers (UPN, EA1, DateAdded)
VALUES (@UPN, @EA1, @DateAdded);
"@

# Process groups
foreach ($groupId in $GroupIds) {
    Write-Host "Processing group: $groupId"

    $members = Get-MgGroupMember -GroupId $groupId  # [web:55]

    foreach ($m in $members) {
        if ($m.AdditionalProperties['@odata.type'] -ne '#microsoft.graph.user') { continue }

        $user = Get-MgUser -UserId $m.Id -Property "userPrincipalName,onPremisesExtensionAttributes"  # [web:55][web:59]
        $upn = $user.UserPrincipalName
        $ea1Value = $user.OnPremisesExtensionAttributes.extensionAttribute1

        $params = @{
            UPN       = $upn
            EA1       = $ea1Value
            DateAdded = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $insertSql -SqlParameters $params  # [web:16]
    }
}
