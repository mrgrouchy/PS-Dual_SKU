# FINAL PowerShell script - RESOLVES GROUP GUIDs to readable GROUP NAMES
# Shows exact group display names assigning each license

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [string]$OutputPath = "LicenseReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Import ALL required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users.Actions

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Group.Read.All"

# Cache for group lookups (performance)
$groupCache = @{}

Write-Host "Reading UPNs from CSV file: $CsvPath" -ForegroundColor Green
$upns = Import-Csv -Path $CsvPath

$result = @()

foreach ($user in $upns) {
    $upn = $user.UPN
    Write-Host "Processing: $upn" -ForegroundColor Yellow

    try {
        # Get user license assignment states
        $mgUser = Get-MgUser -UserId $upn -Property Id,DisplayName,UserPrincipalName,licenseAssignmentStates -ErrorAction Stop

        $licenseAssignments = @()

        foreach ($state in $mgUser.LicenseAssignmentStates) {
            $sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuId -eq $state.SkuId }
            $skuName = if ($sku) { $sku.SkuPartNumber } else { "Unknown: $($state.SkuId)" }

            if ($state.AssignedByGroup) {
                # RESOLVE GROUP GUID to NAME
                if (-not $groupCache[$state.AssignedByGroup]) {
                    try {
                        $group = Get-MgGroup -GroupId $state.AssignedByGroup -Property Id,DisplayName -ErrorAction Stop
                        $groupCache[$state.AssignedByGroup] = $group.DisplayName
                        Write-Host "  Cached group: $($group.DisplayName)" -ForegroundColor Cyan
                    }
                    catch {
                        $groupCache[$state.AssignedByGroup] = "Group not found: $($state.AssignedByGroup)"
                    }
                }
                $groupName = $groupCache[$state.AssignedByGroup]
                $assignmentPath = "GROUP: $groupName"
            } else {
                $assignmentPath = "DIRECT"
            }

            $licenseAssignments += [PSCustomObject]@{
                SkuName = $skuName
                SkuId = $state.SkuId
                AssignmentPath = $assignmentPath
                State = $state.State
                DisabledPlans = ($state.DisabledPlans -join ", ")
            }
        }

        # Build readable summary
        $licensesSummary = ($licenseAssignments | ForEach-Object { "$($_.SkuName): $($_.AssignmentPath)" }) -join " | "
        $directCount = ($licenseAssignments | Where-Object { $_.AssignmentPath -eq "DIRECT" }).Count
        $groupCount = ($licenseAssignments | Where-Object { $_.AssignmentPath -like "GROUP:*" }).Count

        $result += [PSCustomObject]@{
            UPN = $mgUser.UserPrincipalName
            DisplayName = $mgUser.DisplayName
            TotalLicenses = $licenseAssignments.Count
            DirectCount = $directCount
            GroupCount = $groupCount
            LicenseDetails = $licensesSummary
            GroupsUsed = ($licenseAssignments | Where-Object { $_.AssignmentPath -like "GROUP:*" } | ForEach-Object { $_.AssignmentPath -replace 'GROUP: ', '' }) -join '; '
        }

    }
    catch {
        Write-Warning "Failed to process $upn`: $($_.Exception.Message)"
        $result += [PSCustomObject]@{
            UPN = $upn
            DisplayName = "ERROR"
            TotalLicenses = 0
            DirectCount = 0
            GroupCount = 0
            LicenseDetails = "ERROR: $($_.Exception.Message)"
            GroupsUsed = ""
        }
    }
}

# Export results
$result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# Create GROUP SUMMARY report
$groupSummaryPath = $OutputPath -replace '\.csv$', '_ByGroup.csv'
$groupUsage = $result | ForEach-Object {
    $_.PSObject.Properties['GroupsUsed'].Value -split '; ' | ForEach-Object {
        if ($_ -and $_ -ne '') {
            [PSCustomObject]@{ UPN = $_.UPN; DisplayName = $_.DisplayName; GroupName = $_ }
        }
    }
} | Group-Object GroupName | ForEach-Object {
    [PSCustomObject]@{
        GroupName = $_.Name
        UserCount = $_.Count
        Users = ($_.Group | Select-Object -ExpandProperty UPN) -join '; '
    }
} | Sort-Object UserCount -Descending

$groupUsage | Export-Csv -Path $groupSummaryPath -NoTypeInformation -Encoding UTF8

Write-Host "`n✅ Reports created:" -ForegroundColor Green
Write-Host "  📊 User licenses: $OutputPath" -ForegroundColor White
Write-Host "  👥 Group usage: $groupSummaryPath" -ForegroundColor White
Write-Host "  📈 Groups cached: $($groupCache.Count)" -ForegroundColor Magenta

# Final stats
$licensedUsers = ($result | Where-Object { $_.TotalLicenses -gt 0 }).Count
$groupUsers = ($result | Where-Object { $_.GroupCount -gt 0 }).Count
Write-Host "`n📈 STATS:" -ForegroundColor Cyan
Write-Host "  Users processed: $($result.Count)" -ForegroundColor White
Write-Host "  ✅ Licensed users: $licensedUsers" -ForegroundColor Green
Write-Host "  👥 Group-licensed: $groupUsers" -ForegroundColor Magenta

Write-Host "`n=== Script completed ===" -ForegroundColor Green
