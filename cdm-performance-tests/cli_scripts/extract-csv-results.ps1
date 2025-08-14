param(
    [string]$Environment = "local"
)

Write-Host "Running CDM performance tests with environment: $Environment" -ForegroundColor Green
Write-Host "This may take several minutes..." -ForegroundColor Yellow

# Run tests and capture output
$output = bru run --env $Environment 2>&1
$csvResults = $output | Select-String "CSV_RESULT:" | ForEach-Object { 
    $_.ToString() -replace ".*CSV_RESULT:", "" 
}

# Generate filename with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$filename = "cdm-performance-results-$timestamp.csv"

# CSV Header
$header = "Test ID,API Endpoint,Test Description,Test Input Summary,Number of Requests,Concurrent Users,Expected Outcome,Actual Response Time (ms),Throughput (requests/sec),Notes / Observations"

Write-Host "Extracted $($csvResults.Count) test results" -ForegroundColor Green

if ($csvResults.Count -eq 0) {
    Write-Host "No CSV results found! Make sure your tests have CSV_RESULT: output lines" -ForegroundColor Red
    Write-Host "Check the full output:" -ForegroundColor Yellow
    $output | Out-String
    exit 1
}

# Create CSV content
$csvContent = @()
$csvContent += $header
$csvContent += $csvResults

# Write to file with proper encoding
$csvContent | Out-File -FilePath $filename -Encoding UTF8

Write-Host "Results saved to: $filename" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "Total tests: $($csvResults.Count)" -ForegroundColor White

# Show first few results
Write-Host ""
Write-Host "First few results:" -ForegroundColor Cyan
$csvContent | Select-Object -First 4 | ForEach-Object { Write-Host $_ -ForegroundColor White }

if ($csvResults.Count -gt 3) {
    Write-Host "... and $($csvResults.Count - 3) more results" -ForegroundColor Gray
}

Write-Host ""
Write-Host "To open in Excel: Start-Process '$filename'" -ForegroundColor Yellow
Write-Host "To view all results: Get-Content '$filename'" -ForegroundColor Yellow

# Optional: Open in default CSV viewer
$response = Read-Host "Open CSV file now? (y/n)"
if ($response -eq "y" -or $response -eq "Y") {
    Start-Process $filename
}