param(
    [string]$DatabasePath = ".\GroupMembers.sqlite"
)

# --- HARDCODE GROUP IDs ---
$GroupIds = @(
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",  # Group 1
    "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # Group 2
)

# --- Modules ---
Import-Module PSSQLite
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"  # [web:55]

# Ensure DB
if (-not (Test-Path $DatabasePath)) {
    New-Item -ItemType File -Path $DatabasePath -Force | Out-Null
}

# Table
$createTable = @"
CREATE TABLE IF NOT EXISTS GroupMembers (
    Id        INTEGER PRIMARY KEY AUTOINCREMENT,
    UPN       TEXT NOT NULL,
    GroupId   TEXT NOT NULL,
    EA1       TEXT NULL,
    DateAdded TEXT NOT NULL
);
"@
Invoke-SqliteQuery -DataSource $DatabasePath -Query $createTable  # [web:16]

# Process groups
foreach ($groupId in $GroupIds) {
    Write-Host "Processing group: $groupId" -ForegroundColor Yellow

    $members = Get-MgGroupMember -GroupId $groupId -All  # [web:78]
    Write-Host "  Found $($members.Count) members"

    foreach ($m in $members) {
        if ($m.AdditionalProperties['@odata.type'] -ne '#microsoft.graph.user') { continue }

        $user = Get-MgUser -UserId $m.Id -Property "userPrincipalName,onPremisesExtensionAttributes"  # [web:55]
        $upn = $user.UserPrincipalName
        $ea1Value = $user.OnPremisesExtensionAttributes.extensionAttribute1

        # Skip if already exists FOR THIS GROUP
        $existsForGroup = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
            SELECT COUNT(*) as cnt FROM GroupMembers
            WHERE UPN = @UPN AND GroupId = @GroupId;
"@ -SqlParameters @{UPN = $upn; GroupId = $groupId} | Select-Object -ExpandProperty cnt  # [web:16][web:71]

        if ($existsForGroup -eq 0) {
            # Check total UPN count < 2 before insert
            $totalCount = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as cnt FROM GroupMembers WHERE UPN = @UPN;" -SqlParameters @{UPN = $upn} | Select-Object -ExpandProperty cnt  # [web:71]

            if ($totalCount -lt 2) {
                Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
                    INSERT INTO GroupMembers (UPN, GroupId, EA1, DateAdded)
                    VALUES (@UPN, @GroupId, @EA1, @DateAdded);
"@ -SqlParameters @{UPN = $upn; GroupId = $groupId; EA1 = $ea1Value; DateAdded = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")}  # [web:16]
                Write-Host "  Added: $upn [$groupId]" -ForegroundColor Green
            } else {
                Write-Host "  Skip: $upn (max 2 total)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  Skip: $upn [$groupId] exists" -ForegroundColor Gray
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
