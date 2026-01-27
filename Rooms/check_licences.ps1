# Updated PowerShell script - FIXED to properly detect GROUP-BASED license assignments
# Uses licenseAssignmentStates property which shows AssignedByGroup for inherited licenses

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [string]$OutputPath = "LicenseReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Users.Actions

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"

Write-Host "Reading UPNs from CSV file: $CsvPath" -ForegroundColor Green

$upns = Import-Csv -Path $CsvPath

$result = @()

foreach ($user in $upns) {
    $upn = $user.UPN
    Write-Host "Processing: $upn" -ForegroundColor Yellow

    try {
        # Get user with licenseAssignmentStates to detect group assignments
        $mgUser = Get-MgUser -UserId $upn -Property Id,DisplayName,UserPrincipalName,licenseAssignmentStates -ErrorAction Stop

        $licenseAssignments = @()

        # Process licenseAssignmentStates - this shows TRUE assignment paths
        foreach ($state in $mgUser.LicenseAssignmentStates) {
            $sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuId -eq $state.SkuId }
            $skuName = if ($sku) { $sku.SkuPartNumber } else { "Unknown SKU: $($state.SkuId)" }

            $assignmentPath = if ($state.AssignedByGroup) {
                "GROUP: $($state.AssignedByGroup)"
            } else {
                "DIRECT"
            }

            $licenseAssignments += [PSCustomObject]@{
                SkuName = $skuName
                SkuId = $state.SkuId
                State = $state.State
                AssignmentPath = $assignmentPath
                DisabledPlans = ($state.DisabledPlans -join ", ")
            }
        }

        # Summary strings for readable output
        $licensesSummary = ($licenseAssignments | ForEach-Object { "$($_.SkuName) [$($_.AssignmentPath)]" }) -join "; "
        $directCount = ($licenseAssignments | Where-Object { $_.AssignmentPath -eq "DIRECT" }).Count
        $groupCount = ($licenseAssignments | Where-Object { $_.AssignmentPath -like "GROUP:*" }).Count

        $result += [PSCustomObject]@{
            UPN = $mgUser.UserPrincipalName
            DisplayName = $mgUser.DisplayName
            TotalLicenses = $licenseAssignments.Count
            DirectLicenses = $directCount
            GroupLicenses = $groupCount
            LicensesSummary = $licensesSummary
            RawData = ($licenseAssignments | ConvertTo-Json -Depth 3 -Compress) -replace '"', ''
        }

    }
    catch {
        Write-Warning "Failed to process $upn : $($_.Exception.Message)"
        $result += [PSCustomObject]@{
            UPN = $upn
            DisplayName = "ERROR"
            TotalLicenses = 0
            DirectLicenses = 0
            GroupLicenses = 0
            LicensesSummary = "ERROR: $($_.Exception.Message)"
            RawData = $_.Exception.Message
        }
    }
}

# Export detailed results
$result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# Export SUMMARY by assignment type
$summaryPath = $OutputPath -replace '\.csv$', '_Summary.csv'
$result | Select-Object UPN, DisplayName, TotalLicenses, DirectLicenses, GroupLicenses, LicensesSummary |
    Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8

Write-Host "`nReports exported:" -ForegroundColor Green
Write-Host "  Detailed: $OutputPath" -ForegroundColor White
Write-Host "  Summary: $summaryPath" -ForegroundColor White

# Summary stats
$totalUsers = $result.Count
$licensedUsers = ($result | Where-Object { $_.TotalLicenses -gt 0 }).Count
$groupUsers = ($result | Where-Object { $_.GroupLicenses -gt 0 }).Count

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total users: $totalUsers" -ForegroundColor White
Write-Host "With licenses: $licensedUsers" -ForegroundColor Green
Write-Host "With GROUP licenses: $groupUsers" -ForegroundColor Magenta
Write-Host "Avg licenses/user: $([math]::Round(($result | Measure-Object TotalLicenses -Average).Average, 1))" -ForegroundColor White

Disconnect-MgGraph
