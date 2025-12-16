# PowerShell script to detail licensing groups for users from CSV with dual SKUs using Microsoft Graph
# CSV input format: id,DisplayName,UserPrincipalName

# Install and import required modules
if (-not (Get-Module Microsoft.Graph.Groups -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All"

# Get CSV file path (modify as needed)
$csvPath = Read-Host "Enter path to CSV file with dual license users (id,DisplayName,UserPrincipalName)"

if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found: $csvPath"
    return
}

# Import users from CSV
$dualLicenseUsers = Import-Csv $csvPath

Write-Host "Loaded $($dualLicenseUsers.Count) users from CSV" -ForegroundColor Green

# Get SKU details for verification
$enterprisePremiumSku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPREMIUM" }
$speE5Sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }

Write-Host "ENTERPRISEPREMIUM SKU ID: $($enterprisePremiumSku.SkuId)" -ForegroundColor Green
Write-Host "SPE_E5 SKU ID: $($speE5Sku.SkuId)" -ForegroundColor Green

# Detailed group analysis for each CSV user
$groupReport = foreach ($user in $dualLicenseUsers) {
    Write-Progress -Activity "Analyzing groups" -Status $user.DisplayName -PercentComplete (($dualLicenseUsers.IndexOf($user) / $dualLicenseUsers.Count) * 100)
    
    try {
        # Verify user still has both licenses
        $licenses = Get-MgUserLicenseDetail -UserId $user.id | Select-Object -ExpandProperty SkuId
        if (-not ($licenses -contains $enterprisePremiumSku.SkuId -and $licenses -contains $speE5Sku.SkuId)) {
            continue
        }
        
        # Get all group memberships
        $groups = Get-MgUserMemberOf -UserId $user.id -All | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' }
        
        # Categorize groups by license assignment type
        $licenseGroups = @()
        
        foreach ($group in $groups) {
            $groupDetails = Get-MgGroup -GroupId $group.Id -Property Id, DisplayName, GroupTypes, LicenseProcessingState -ErrorAction SilentlyContinue
            if (-not $groupDetails) { continue }
            
            $groupType = if ($groupDetails.GroupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Static' }
            
            # Check if group assigns licenses
            $skuAssignments = $groupDetails.LicenseProcessingState.AssignedLicenses
            $hasEnterprisePremium = $skuAssignments.SkuId -contains $enterprisePremiumSku.SkuId
            $hasSPE5 = $skuAssignments.SkuId -contains $speE5Sku.SkuId
            
            $licenseType = switch ($true) {
                ($hasEnterprisePremium -and $hasSPE5) { 'Both SKUs' }
                $hasEnterprisePremium { 'ENTERPRISEPREMIUM' }
                $hasSPE5 { 'SPE_E5' }
                default { 'No Licenses' }
            }
            
            $licenseGroups += [PSCustomObject]@{
                GroupName = $groupDetails.DisplayName
                GroupId = $groupDetails.Id
                GroupType = $groupType
                LicenseAssignment = $licenseType
            }
        }
        
        [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            UserId = $user.id
            TotalGroups = $groups.Count
            LicenseAssigningGroups = ($licenseGroups | Where-Object { $_.LicenseAssignment -ne 'No Licenses' }).Count
            BothSKUGroups = ($licenseGroups | Where-Object { $_.LicenseAssignment -eq 'Both SKUs' }).Count
            EnterprisePremiumGroups = ($licenseGroups | Where-Object { $_.LicenseAssignment -eq 'ENTERPRISEPREMIUM' }).Count
            SPE5Groups = ($licenseGroups | Where-Object { $_.LicenseAssignment -eq 'SPE_E5' }).Count
            GroupsDetail = ($licenseGroups | ConvertTo-Json -Depth 3)
        }
    }
    catch {
        Write-Warning "Error processing user $($user.DisplayName): $($_.Exception.Message)"
    }
}

# Display summary
Write-Host "`n=== CSV USERS GROUP SUMMARY ===" -ForegroundColor Cyan
$groupReport | Select-Object DisplayName, UserPrincipalName, TotalGroups, LicenseAssigningGroups, BothSKUGroups, EnterprisePremiumGroups, SPE5Groups | Format-Table -AutoSize

# Summary by license assignment type
Write-Host "`n=== SUMMARY BY LICENSE ASSIGNMENT TYPE ===" -ForegroundColor Cyan
$licenseAssignmentSummary = $groupReport | ForEach-Object { 
    $_.GroupsDetail | ConvertFrom-Json 
} | Where-Object { $_.LicenseAssignment -ne 'No Licenses' } | 
Group-Object LicenseAssignment | Select-Object Name, @{N='Total Groups';E={$_.Count}}

$licenseAssignmentSummary | Format-Table -AutoSize

# Export reports
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$groupReport | Select-Object DisplayName, UserPrincipalName, UserId, TotalGroups, LicenseAssigningGroups, BothSKUGroups, EnterprisePremiumGroups, SPE5Groups | 
    Export-Csv -Path "CSV_DualLicenseUsers_GroupSummary_$timestamp.csv" -NoTypeInformation

# Full detailed report
$fullReport = foreach ($user in $groupReport) {
    $userGroups = $user.GroupsDetail | ConvertFrom-Json
    foreach ($group in $userGroups) {
        [PSCustomObject]@{
            UserDisplayName = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            UserId = $user.UserId
            GroupName = $group.GroupName
            GroupId = $group.GroupId
            GroupType = $group.GroupType
            LicenseAssignment = $group.LicenseAssignment
        }
    }
}
$fullReport | Export-Csv -Path "CSV_DualLicenseUsers_FullGroups_$timestamp.csv" -NoTypeInformation

Write-Host "`nReports exported:" -ForegroundColor Green
Write-Host "  - Summary: CSV_DualLicenseUsers_GroupSummary_$timestamp.csv"
Write-Host "  - Full Details: CSV_DualLicenseUsers_FullGroups_$timestamp.csv"
Write-Host "Disconnect with: Disconnect-MgGraph" -ForegroundColor Cyan
