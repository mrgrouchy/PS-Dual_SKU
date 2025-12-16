# Prereqs: your CSV already imported to $dualLicenseUsers (id,DisplayName,UserPrincipalName)
# Graph connection & SKU lookup unchanged

# Make a hash of SkuId → SkuPartNumber for readability
$skus = Get-MgSubscribedSku
$skuMap = @{}
foreach ($s in $skus) { $skuMap[$s.SkuId] = $s.SkuPartNumber }

$report = foreach ($user in $dualLicenseUsers) {
    # Get license assignment states for this user (includes AssignedByGroup + SkuId + plans)
    $las = Get-MgUser -UserId $user.id -Property Id,DisplayName,AssignedLicenses,LicenseAssignmentStates |
           Select-Object -ExpandProperty LicenseAssignmentStates

    # Only look at successful, active assignments
    $effectiveLicenses = $las | Where-Object { $_.Error -eq 'None' -and $_.State -eq 'Active' }

    # Filter to your two SKUs
    $dualSkuAssignments = $effectiveLicenses | Where-Object {
        $_.SkuId -in @($enterprisePremiumSku.SkuId, $speE5Sku.SkuId)
    }

    foreach ($assign in $dualSkuAssignments) {
        # If AssignedByGroup is populated, that group contributed this SKU (or its plans)
        $groupId = $assign.AssignedByGroup
        $groupName = $null

        if ($groupId) {
            $g = Get-MgGroup -GroupId $groupId -Property Id,DisplayName,GroupTypes -ErrorAction SilentlyContinue
            if ($g) { $groupName = $g.DisplayName }
        }

        [PSCustomObject]@{
            UserDisplayName     = $user.DisplayName
            UserPrincipalName   = $user.UserPrincipalName
            UserId              = $user.id
            SkuId               = $assign.SkuId
            SkuPartNumber       = $skuMap[$assign.SkuId]
            AssignedByGroupId   = $groupId
            AssignedByGroupName = $groupName
            # Plans disabled by this assignment (if you care about components)
            DisabledPlans       = ($assign.DisabledPlans -join ';')
            AssignmentState     = $assign.State
        }
    }
}

# Export: shows, per user & SKU, exactly which group assigned it (and which plans were disabled)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$report | Export-Csv "DualSku_GroupAssignments_$timestamp.csv" -NoTypeInformation
