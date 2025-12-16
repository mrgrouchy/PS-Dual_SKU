<#
    Purpose:
      For a set of users (from CSV), show which groups assign ENTERPRISEPREMIUM and/or SPE_E5,
      using LicenseAssignmentStates so partial/service-plan assignments are correctly represented.

    CSV format:
      id,DisplayName,UserPrincipalName

    Requirements:
      - Microsoft.Graph PowerShell SDK
      - Permissions: User.Read.All, Group.Read.All, Directory.Read.All
#>

# ----------------------------
# Module setup
# ----------------------------
if (-not (Get-Module Microsoft.Graph.Users -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
if (-not (Get-Module Microsoft.Graph.Groups -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# ----------------------------
# Connect to Graph
# ----------------------------
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All"

# ----------------------------
# CSV input
# ----------------------------
$csvPath = Read-Host "Enter path to CSV file with users (id,DisplayName,UserPrincipalName)"

if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found: $csvPath"
    return
}

$usersFromCsv = Import-Csv $csvPath
Write-Host "Loaded $($usersFromCsv.Count) users from CSV" -ForegroundColor Green

# ----------------------------
# Get license SKUs and build map
# ----------------------------
$allSkus = Get-MgSubscribedSku

$enterprisePremiumSku = $allSkus | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPREMIUM" }
$speE5Sku             = $allSkus | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }

if (-not $enterprisePremiumSku -or -not $speE5Sku) {
    Write-Error "Could not find ENTERPRISEPREMIUM and/or SPE_E5 in your tenant. Check Get-MgSubscribedSku."
    $allSkus | Select-Object SkuPartNumber,SkuId | Format-Table
    return
}

Write-Host "ENTERPRISEPREMIUM SkuId: $($enterprisePremiumSku.SkuId)" -ForegroundColor Green
Write-Host "SPE_E5           SkuId: $($speE5Sku.SkuId)" -ForegroundColor Green

# Simple hash for SkuId → SkuPartNumber
$skuMap = @{}
foreach ($s in $allSkus) {
    $skuMap[$s.SkuId] = $s.SkuPartNumber
}

# ----------------------------
# Process users and build report
# ----------------------------
$report = @()
$idx = 0
$total = $usersFromCsv.Count

foreach ($user in $usersFromCsv) {
    $idx++

    $percent = [int](($idx / $total) * 100)
    Write-Progress -Activity "Processing users" -Status $user.DisplayName -PercentComplete $percent

    try {
        # Get licenseAssignmentStates for this user
        $u = Get-MgUser -UserId $user.id -Property Id,DisplayName,UserPrincipalName,AssignedLicenses,LicenseAssignmentStates

        if (-not $u.LicenseAssignmentStates) {
            continue
        }

        # Effective (no error, active) assignments only
        $effective = $u.LicenseAssignmentStates |
                     Where-Object { $_.Error -eq "None" -and $_.State -eq "Active" }

        # Filter to the two SKUs of interest
        $dualSkuAssignments = $effective | Where-Object {
            $_.SkuId -in @($enterprisePremiumSku.SkuId, $speE5Sku.SkuId)
        }

        foreach ($assign in $dualSkuAssignments) {
            $skuId   = $assign.SkuId
            $skuName = $skuMap[$skuId]

            # AssignedByGroup = GUID of group if group-based, $null if direct
            $groupId   = $assign.AssignedByGroup
            $groupName = $null
            $groupType = $null

            if ($groupId) {
                $g = Get-MgGroup -GroupId $groupId -Property Id,DisplayName,GroupTypes -ErrorAction SilentlyContinue
                if ($g) {
                    $groupName = $g.DisplayName
                    $groupType = if ($g.GroupTypes -contains "DynamicMembership") { "Dynamic" } else { "Static" }
                }
            }

            # DisabledPlans is an array of GUIDs of service plans disabled for this assignment
            $disabledPlans = $null
            if ($assign.DisabledPlans) {
                $disabledPlans = $assign.DisabledPlans -join ";"
            }

            $report += [PSCustomObject]@{
                UserDisplayName       = $u.DisplayName
                UserPrincipalName     = $u.UserPrincipalName
                UserId                = $u.Id
                SkuId                 = $skuId
                SkuPartNumber         = $skuName
                AssignmentState       = $assign.State          # normally 'Active'
                AssignmentError       = $assign.Error          # normally 'None'
                AssignedByGroupId     = $groupId               # null = direct assignment
                AssignedByGroupName   = $groupName
                AssignedByGroupType   = $groupType             # Dynamic / Static / null
                DisabledPlans         = $disabledPlans         # which components of the SKU are disabled
            }
        }
    }
    catch {
        Write-Warning "Error processing user $($user.DisplayName) [$($user.id)]: $($_.Exception.Message)"
    }
}

# ----------------------------
# Optional: show quick on-screen summary
# ----------------------------
Write-Host "`n=== ASSIGNMENT SUMMARY (ENTERPRISEPREMIUM & SPE_E5) ===" -ForegroundColor Cyan

$report | Group-Object SkuPartNumber | ForEach-Object {
    "{0,-20} : {1,5} assignments" -f $_.Name, $_.Count
}

Write-Host "`nAssignments by source (Group vs Direct):" -ForegroundColor Cyan

$report | ForEach-Object {
    if ($_.AssignedByGroupId) { "Group" } else { "Direct" }
} | Group-Object | ForEach-Object {
    "{0,-6} : {1,5}" -f $_.Name, $_.Count
}

# ----------------------------
# Export to CSV
# ----------------------------
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = "DualSku_AssignmentPaths_$timestamp.csv"

$report |
    Sort-Object UserPrincipalName,SkuPartNumber,AssignedByGroupName |
    Export-Csv -Path $outFile -NoTypeInformation

Write-Host "`nReport exported to: $outFile" -ForegroundColor Green
Write-Host "Disconnect with: Disconnect-MgGraph"
