# PowerShell script to compare users in ENTERPRISEPREMIUM and SPE_E5 license SKUs using Microsoft Graph
# Requires Microsoft.Graph PowerShell module and User.Read.All, Organization.Read.All permissions

# Install and import required module if not present
if (-not (Get-Module Microsoft.Graph.Users -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All"

# Get SKU details for both licenses
$enterprisePremiumSku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPREMIUM" }
$speE5Sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }

if (-not $enterprisePremiumSku -or -not $speE5Sku) {
    Write-Error "One or both SKUs not found in tenant. Available SKUs:"
    Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId | Format-Table
    return
}

Write-Host "ENTERPRISEPREMIUM SKU ID: $($enterprisePremiumSku.SkuId)" -ForegroundColor Green
Write-Host "SPE_E5 SKU ID: $($speE5Sku.SkuId)" -ForegroundColor Green

# Get all users with their licenses (using licenseDetails for complete info)
$allUsers = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AssignedLicenses, LicenseDetails | 
            ForEach-Object { 
                $userLicenses = Get-MgUserLicenseDetail -UserId $_.Id
                [PSCustomObject]@{
                    Id = $_.Id
                    DisplayName = $_.DisplayName
                    UserPrincipalName = $_.UserPrincipalName
                    EnterprisePremium = ($userLicenses.SkuId -contains $enterprisePremiumSku.SkuId)
                    SPE_E5 = ($userLicenses.SkuId -contains $speE5Sku.SkuId)
                }
            }

# Categorize users
$onlyEnterprisePremium = $allUsers | Where-Object { $_.EnterprisePremium -and -not $_.SPE_E5 }
$onlySPE_E5 = $allUsers | Where-Object { $_.SPE_E5 -and -not $_.EnterprisePremium }
$bothLicenses = $allUsers | Where-Object { $_.EnterprisePremium -and $_.SPE_E5 }
$neither = $allUsers | Where-Object { -not $_.EnterprisePremium -and -not $_.SPE_E5 }

# Display comparison results
Write-Host "`n=== LICENSE COMPARISON RESULTS ===" -ForegroundColor Cyan
Write-Host "Users with ONLY ENTERPRISEPREMIUM ($($onlyEnterprisePremium.Count)): " -ForegroundColor Yellow
$onlyEnterprisePremium | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize

Write-Host "`nUsers with ONLY SPE_E5 ($($onlySPE_E5.Count)): " -ForegroundColor Yellow
$onlySPE_E5 | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize

Write-Host "`nUsers with BOTH licenses ($($bothLicenses.Count)): " -ForegroundColor Magenta
$bothLicenses | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize

Write-Host "`nUsers with NEITHER license ($($neither.Count)): " -ForegroundColor Gray

# Export detailed comparison to CSV
$result = [PSCustomObject]@{
    'Only ENTERPRISEPREMIUM Count' = $onlyEnterprisePremium.Count
    'Only SPE_E5 Count' = $onlySPE_E5.Count
    'Both Licenses Count' = $bothLicenses.Count
    'Total Users Analyzed' = $allUsers.Count
}
$result | Export-Csv -Path "LicenseComparison_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation

# Detailed export
$allUsers | Export-Csv -Path "AllUsersLicenseDetails_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation

Write-Host "`nDetailed reports exported to CSV files." -ForegroundColor Green
Write-Host "Disconnect with: Disconnect-MgGraph" -ForegroundColor Cyan
