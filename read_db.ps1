param(
    [string]$DatabasePath = ".\GroupMembers.sqlite"
)

# Ensure module and DB
Import-Module PSSQLite
if (-not (Test-Path $DatabasePath)) {
    Write-Error "DB not found: $DatabasePath"
    exit 1
}

# View full table
Write-Host "Full table contents:" -ForegroundColor Green
Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT * FROM GroupMembers ORDER BY DateAdded DESC;" | Format-Table -AutoSize  # [web:16][web:23]

# Quick stats
Write-Host "`nRow count:" -ForegroundColor Green
(Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as TotalRows FROM GroupMembers;").TotalRows  # [web:16]

# Users with EA1 populated
Write-Host "`nUsers with EA1:" -ForegroundColor Green
Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT UPN, EA1 FROM GroupMembers WHERE EA1 IS NOT NULL ORDER BY UPN;" | Format-Table -AutoSize  # [web:16]
