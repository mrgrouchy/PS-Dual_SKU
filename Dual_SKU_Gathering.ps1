# PowerShell script to compare users in ENTERPRISEPREMIUM and SPE_E5 license SKUs using Microsoft Graph
# Enhanced with progress bars and visual reporting
# Requires Microsoft.Graph PowerShell module and User.Read.All, Organization.Read.All permissions

# Install and import required module if not present
if (-not (Get-Module Microsoft.Graph.Users -ListAvailable)) {
    Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All"
Write-Host "Connected successfully!" -ForegroundColor Green

# Get total user count for progress tracking
Write-Host "Getting total user count..." -ForegroundColor Cyan
$totalUsers = (Get-MgUser -All -CountVariable userCount -ConsistencyLevel eventual).Count
Write-Host "Found $totalUsers total users in tenant." -ForegroundColor Green

# Get SKU details for both licenses
Write-Progress -Activity "Analyzing Licenses" -Status "Getting SKU details" -PercentComplete 5
$enterprisePremiumSku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPREMIUM" }
$speE5Sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }

if (-not $enterprisePremiumSku -or -not $speE5Sku) {
    Write-Error "One or both SKUs not found in tenant. Available SKUs:"
    Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId | Format-Table
    Disconnect-MgGraph
    return
}

Write-Host "`nENTERPRISEPREMIUM SKU ID: $($enterprisePremiumSku.SkuId)" -ForegroundColor Green
Write-Host "SPE_E5 SKU ID: $($speE5Sku.SkuId)" -ForegroundColor Green

# Get all users with their licenses (with progress bar)
Write-Progress -Activity "Analyzing User Licenses" -Status "Processing users" -PercentComplete 10
$allUsers = @()
$userCounter = 0

Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AssignedLicenses, LicenseDetails | 
ForEach-Object { 
    $userCounter++
    $percentComplete = [math]::Min(90, ($userCounter / $totalUsers) * 100)
    Write-Progress -Activity "Analyzing User Licenses ($userCounter/$totalUsers)" -Status "Processing $($_.DisplayName)" -PercentComplete $percentComplete
    
    $userLicenses = Get-MgUserLicenseDetail -UserId $_.Id
    [PSCustomObject]@{
        Id = $_.Id
        DisplayName = $_.DisplayName
        UserPrincipalName = $_.UserPrincipalName
        EnterprisePremium = ($userLicenses.SkuId -contains $enterprisePremiumSku.SkuId)
        SPE_E5 = ($userLicenses.SkuId -contains $speE5Sku.SkuId)
    }
} | ForEach-Object { $allUsers += $_ }

Write-Progress -Activity "Analyzing User Licenses" -Completed

# Categorize users with progress visualization
Write-Progress -Activity "Categorizing Users" -Status "Analyzing license combinations" -PercentComplete 95

$onlyEnterprisePremium = $allUsers | Where-Object { $_.EnterprisePremium -and -not $_.SPE_E5 }
$onlySPE_E5 = $allUsers | Where-Object { $_.SPE_E5 -and -not $_.EnterprisePremium }
$bothLicenses = $allUsers | Where-Object { $_.EnterprisePremium -and $_.SPE_E5 }
$neither = $allUsers | Where-Object { -not $_.EnterprisePremium -and -not $_.SPE_E5 }

Write-Progress -Activity "Categorizing Users" -Completed

# Visual progress summary
Clear-Host
Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                       LICENSE ANALYSIS COMPLETE                      ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Total Users Analyzed: $totalUsers                                   ║" -ForegroundColor White
Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  📊 ENTERPRISEPREMIUM only: $($onlyEnterprisePremium.Count)        ║" -ForegroundColor Yellow
Write-Host "║  🔵 SPE_E5 only: $($onlySPE_E5.Count)                              ║" -ForegroundColor Blue
Write-Host "║  🟣 BOTH licenses: $($bothLicenses.Count)                          ║" -ForegroundColor Magenta
Write-Host "║  ⚪ NEITHER license: $($neither.Count)                              ║" -ForegroundColor Gray
Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Progress bar visualization for each category
$barWidth = 50
Write-Host "`n📈 License Distribution Chart:" -ForegroundColor Cyan

# EnterprisePremium only bar
$epPercent = [math]::Round(($onlyEnterprisePremium.Count / $totalUsers) * 100, 1)
$epBarLength = [math]::Round(($onlyEnterprisePremium.Count / $totalUsers) * $barWidth)
Write-Host ("ENTERPRISEPREMIUM only [{0}{1}] {2,5:F1}% ({3})" -f 
    ('█' * $epBarLength), 
    ('░' * ($barWidth - $epBarLength)), 
    $epPercent, 
    $onlyEnterprisePremium.Count) -ForegroundColor Yellow

# SPE_E5 only bar
$spePercent = [math]::Round(($onlySPE_E5.Count / $totalUsers) * 100, 1)
$speBarLength = [math]::Round(($onlySPE_E5.Count / $totalUsers) * $barWidth)
Write-Host ("SPE_E5 only         [{0}{1}] {2,5:F1}% ({3})" -f 
    ('█' * $speBarLength), 
    ('░' * ($barWidth - $speBarLength)), 
    $spePercent, 
    $onlySPE_E5.Count) -ForegroundColor Blue

# Both licenses bar
$bothPercent = [math]::Round(($bothLicenses.Count / $totalUsers) * 100, 1)
$bothBarLength = [math]::Round(($bothLicenses.Count / $totalUsers) * $barWidth)
Write-Host ("BOTH licenses       [{0}{1}] {2,5:F1}% ({3})" -f 
    ('█' * $bothBarLength), 
    ('░' * ($barWidth - $bothBarLength)), 
    $bothPercent, 
    $bothLicenses.Count) -ForegroundColor Magenta

# Neither bar
$neitherPercent = [math]::Round(($neither.Count / $totalUsers) * 100, 1)
$neitherBarLength = [math]::Round(($neither.Count / $totalUsers) * $barWidth)
Write-Host ("NEITHER license     [{0}{1}] {2,5:F1}% ({3})" -f 
    ('█' * $neitherBarLength), 
    ('░' * ($barWidth - $neitherBarLength)), 
    $neitherPercent, 
    $neither.Count) -ForegroundColor Gray

# Detailed results tables
Write-Host "`n=== DETAILED RESULTS ===" -ForegroundColor Cyan

if ($onlyEnterprisePremium.Count -gt 0) {
    Write-Host "`n👥 Users with ONLY ENTERPRISEPREMIUM ($($onlyEnterprisePremium.Count)):" -ForegroundColor Yellow
    $onlyEnterprisePremium | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize
}

if ($onlySPE_E5.Count -gt 0) {
    Write-Host "`n🔵 Users with ONLY SPE_E5 ($($onlySPE_E5.Count)):" -ForegroundColor Blue
    $onlySPE_E5 | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize
}

if ($bothLicenses.Count -gt 0) {
    Write-Host "`n🟣 Users with BOTH licenses ($($bothLicenses.Count)):" -ForegroundColor Magenta
    $bothLicenses | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize
}

# Export summary with progress
Write-Progress -Activity "Exporting Reports" -Status "Creating CSV files" -PercentComplete 98
$resultSummary = [PSCustomObject]@{
    'Timestamp' = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    'Total Users Analyzed' = $totalUsers
    'Only ENTERPRISEPREMIUM Count' = $onlyEnterprisePremium.Count
    'Only SPE_E5 Count' = $onlySPE_E5.Count
    'Both Licenses Count' = $bothLicenses.Count
    'Neither License Count' = $neither.Count
    'EP Only %' = "{0:F1}" -f $epPercent
    'SPE Only %' = "{0:F1}" -f $spePercent
    'Both %' = "{0:F1}" -f $bothPercent
    'Neither %' = "{0:F1}" -f $neitherPercent
}
$summaryFile = "LicenseComparison_Summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$resultSummary | Export-Csv -Path $summaryFile -NoTypeInformation

$allUsers | Export-Csv -Path "AllUsersLicenseDetails_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation

Write-Progress -Activity "Exporting Reports" -Completed

# Final status
Write-Host "`n✅ ANALYSIS COMPLETE!" -ForegroundColor Green
Write-Host "📁 Summary report: $summaryFile" -ForegroundColor Green
Write-Host "📁 Detailed users: AllUsersLicenseDetails_*.csv" -ForegroundColor Green
Write-Host "`n💡 To disconnect: Disconnect-MgGraph" -ForegroundColor Cyan
