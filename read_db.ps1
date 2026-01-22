param(
    [string]$DatabasePath = ".\GroupMembers.sqlite"
)

Import-Module PSSQLite
if (-not (Test-Path $DatabasePath)) {
    Write-Error "DB not found: $DatabasePath"
    exit 1
}

Write-Host "=== GroupMembers DB Report ===" -ForegroundColor Green

# Totals
$totalRows = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Total FROM GroupMembers;").Total  # [web:16]
$uniqueUPNs = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(DISTINCT UPN) as Unique FROM GroupMembers;").Unique  # [web:93]

Write-Host "Total rows: $totalRows | Unique users: $uniqueUPNs" -ForegroundColor Cyan

# Per-group breakdown (auto-detects)
$groupStats = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
    SELECT GroupId,
           COUNT(*) as MemberCount,
           COUNT(DISTINCT UPN) as UniquePerGroup
    FROM GroupMembers
    GROUP BY GroupId
    ORDER BY MemberCount DESC;
"@  # [web:93][web:94]

Write-Host "`nPer-group stats:" -ForegroundColor Yellow
$groupStats | Format-Table -AutoSize

# Cross-group duplicates
$duplicates = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
    SELECT UPN,
           COUNT(DISTINCT GroupId) as Groups,
           GROUP_CONCAT(DISTINCT GroupId) as GroupIds
    FROM GroupMembers
    GROUP BY UPN
    HAVING Groups > 1
    ORDER BY UPN;
"@  # [web:93]

Write-Host "`nUsers in multiple groups: $($duplicates.Count)" -ForegroundColor Magenta
if ($duplicates.Count -gt 0) {
    $duplicates | Format-Table -AutoSize
}

# EA1 summary
$ea1Stats = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
    SELECT
        CASE WHEN EA1 IS NULL THEN 'No EA1' ELSE 'Has EA1' END as EA1Status,
        COUNT(*) as Count
    FROM GroupMembers
    GROUP BY EA1Status;
"@
Write-Host "`nEA1 coverage:" -ForegroundColor Cyan
$ea1Stats | Format-Table -AutoSize

Write-Host "`nRecent 5 rows:" -ForegroundColor Green
Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT * FROM GroupMembers ORDER BY DateAdded DESC LIMIT 5;" | Format-Table Id, UPN, GroupId, EA1 -Wrap  # [web:16]

Write-Host "`n=== End ===" -ForegroundColor Green
