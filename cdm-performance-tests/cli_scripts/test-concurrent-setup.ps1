# Quick test to verify concurrent testing setup
param(
    [string]$Environment = "local"
)

Write-Host "Testing concurrent setup..." -ForegroundColor Green

# Test 1: Check if files exist
$requiredFiles = @(
    "environments/$Environment.bru",
    "cli_scripts/extract-csv-results-concurrent.ps1"
)

Write-Host "`nChecking required files:" -ForegroundColor Cyan
foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "OK $file" -ForegroundColor Green
    } else {
        Write-Host "MISSING $file" -ForegroundColor Red
    }
}

# Test 2: Verify environment file can be parsed
try {
    Write-Host "`nTesting environment parsing:" -ForegroundColor Cyan
    $envContent = Get-Content "environments/$Environment.bru" -ErrorAction Stop
    $baseUrlLine = $envContent | Where-Object { $_ -match "baseUrl:" }
    if ($baseUrlLine) {
        Write-Host "OK Environment file parsed successfully" -ForegroundColor Green
        Write-Host "  Base URL found: $($baseUrlLine.Split(':')[1].Trim())" -ForegroundColor Gray
    } else {
        Write-Host "ERROR No baseUrl found in environment file" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR parsing environment file: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nSetup test complete!" -ForegroundColor Green