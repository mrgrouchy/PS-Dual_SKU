# PowerShell script to check Microsoft 365 licenses and assignment paths for UPNs from CSV
# Requires Microsoft Graph PowerShell module: Install-Module Microsoft.Graph -Scope CurrentUser

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [string]$OutputPath = "LicenseReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Users.Actions

# Connect to Microsoft Graph (interactive login)
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"

Write-Host "Reading UPNs from CSV file: $CsvPath" -ForegroundColor Green

# Import CSV (expects column named 'UPN')
$upns = Import-Csv -Path $CsvPath

$result = @()

foreach ($user in $upns) {
    $upn = $user.UPN
    Write-Host "Processing: $upn" -ForegroundColor Yellow

    try {
        # Get user details
        $mgUser = Get-MgUser -UserId $upn -Property Id,DisplayName,UserPrincipalName -ErrorAction Stop

        # Get assigned licenses
        $licenses = Get-MgUserLicenseDetail -UserId $mgUser.Id

        $licenseInfo = @()
        foreach ($license in $licenses) {
            $sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuId -eq $license.SkuId }
            $licenseDisplay = if ($sku) { "$($sku.SkuPartNumber) ($($license.SkuId))" } else { $license.SkuId }

            # Get license assignment details
            $assignmentPath = "Direct"  # Default
            if ($license.AssignedBy) {
                $assignmentPath = "Group-assigned: $($license.AssignedBy)"
            }

            $licenseInfo += [PSCustomObject]@{
                SkuPartNumber = $sku.SkuPartNumber
                SkuId = $license.SkuId
                AssignmentPath = $assignmentPath
            }
        }

        $result += [PSCustomObject]@{
            UPN = $mgUser.UserPrincipalName
            DisplayName = $mgUser.DisplayName
            LicenseCount = $licenses.Count
            Licenses = ($licenseInfo | ForEach-Object { "$($_.SkuPartNumber) [$($_.AssignmentPath)]" }) -join "; "
            RawLicenseData = ($licenseInfo | ConvertTo-Json -Compress) -replace '"', ''
        }

    }
    catch {
        Write-Warning "Failed to process $upn : $($_.Exception.Message)"
        $result += [PSCustomObject]@{
            UPN = $upn
            DisplayName = "N/A"
            LicenseCount = 0
            Licenses = "User not found or access denied"
            RawLicenseData = $_.Exception.Message
        }
    }
}

# Export results
$result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Report exported to: $OutputPath" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph

# Display summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "Total users processed: $($result.Count)" -ForegroundColor White
Write-Host "Users with licenses: $(($result | Where-Object { $_.LicenseCount -gt 0 }).Count)" -ForegroundColor Green
Write-Host "Users without licenses: $(($result | Where-Object { $_.LicenseCount -eq 0 -and $_.Licenses -notlike '*not found*' }).Count)" -ForegroundColor Red
