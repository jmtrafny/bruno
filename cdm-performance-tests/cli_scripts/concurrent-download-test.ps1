param(
    [string]$Environment = "local",
    [int[]]$ConcurrentUsers = @(10, 25, 50),
    [switch]$OutputCSVOnly = $false
)

# Load environment variables based on Bruno environment files
function Get-BrunoEnvironment {
    param([string]$EnvName)
    
    $envFile = "environments/$EnvName.bru"
    if (-not (Test-Path $envFile)) {
        throw "Environment file not found: $envFile"
    }
    
    $envVars = @{}
    $content = Get-Content $envFile
    $inVarsSection = $false
    
    foreach ($line in $content) {
        if ($line.Trim() -eq "vars {") {
            $inVarsSection = $true
            continue
        }
        if ($line.Trim() -eq "}") {
            $inVarsSection = $false
            continue
        }
        if ($inVarsSection -and $line.Contains(":")) {
            $parts = $line.Split(":", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            $envVars[$key] = $value
        }
    }
    
    return $envVars
}

# Function to make a single HTTP request
function Invoke-DownloadRequest {
    param(
        [string]$BaseUrl,
        [string]$TestBucket,
        [string]$ScratchPath,
        [int]$RequestId,
        [string]$TestId
    )
    
    $startTime = Get-Date
    
    $body = @{
        sourceBucket = $TestBucket
        sourcePrefix = "test-data/small-dataset"
        destinationPath = "$ScratchPath/cdm-perf/concurrent-$TestId-$RequestId"
    } | ConvertTo-Json
    
    $headers = @{
        'Content-Type' = 'application/json'
        'userId' = '3129426'
        'transactionId' = '6249213'
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/directory/download" -Method POST -Body $body -Headers $headers -ErrorAction Stop
        $endTime = Get-Date
        $responseTime = ($endTime - $startTime).TotalMilliseconds
        
        return @{
            Success = $true
            ResponseTime = [int]$responseTime
            HttpStatus = 200
            ApiStatus = $response.status
            FileCount = $response.data.fileCount
            Error = $null
        }
    }
    catch {
        $endTime = Get-Date
        $responseTime = ($endTime - $startTime).TotalMilliseconds
        
        return @{
            Success = $false
            ResponseTime = [int]$responseTime
            HttpStatus = $_.Exception.Response.StatusCode.value__ ?? 0
            ApiStatus = "ERROR"
            FileCount = 0
            Error = $_.Exception.Message
        }
    }
}

# Function to run concurrent test
function Start-ConcurrentTest {
    param(
        [int]$UserCount,
        [string]$TestId,
        [hashtable]$EnvVars
    )
    
    if (-not $OutputCSVOnly) {
        Write-Host "`n=== Starting Test $TestId - $UserCount Concurrent Users ===" -ForegroundColor Cyan
    }
    
    $startTime = Get-Date
    
    # Create concurrent jobs
    $jobs = @()
    for ($i = 1; $i -le $UserCount; $i++) {
        $job = Start-Job -ScriptBlock {
            param($BaseUrl, $TestBucket, $ScratchPath, $RequestId, $TestId, $FunctionDef)
            
            # Import the function into the job's scope
            Invoke-Expression $FunctionDef
            
            Invoke-DownloadRequest -BaseUrl $BaseUrl -TestBucket $TestBucket -ScratchPath $ScratchPath -RequestId $RequestId -TestId $TestId
        } -ArgumentList $EnvVars.baseUrl, $EnvVars.testBucket, $EnvVars.scratchPath, $i, $TestId, (Get-Content Function:\Invoke-DownloadRequest -Raw)
        
        $jobs += $job
    }
    
    # Wait for all jobs to complete and collect results
    $results = @()
    foreach ($job in $jobs) {
        $result = Receive-Job -Job $job -Wait
        $results += $result
        Remove-Job -Job $job
    }
    
    $totalTime = (Get-Date) - $startTime
    
    # Calculate metrics
    $responseTimes = $results | ForEach-Object { $_.ResponseTime }
    $avgResponseTime = ($responseTimes | Measure-Object -Average).Average
    $minResponseTime = ($responseTimes | Measure-Object -Minimum).Minimum
    $maxResponseTime = ($responseTimes | Measure-Object -Maximum).Maximum
    $successfulRequests = ($results | Where-Object { $_.Success }).Count
    $throughput = [math]::Round($UserCount / $totalTime.TotalSeconds, 2)
    
    # Performance evaluation
    $threshold = [int]$EnvVars.concurrentThreshold
    $successRate = $successfulRequests / $UserCount
    $performancePass = ($avgResponseTime -lt $threshold) -and ($successRate -ge 0.95)
    
    if (-not $OutputCSVOnly) {
        Write-Host "Total Test Duration: $($totalTime.TotalMilliseconds.ToString('F0'))ms" -ForegroundColor White
        Write-Host "Average Response Time: $($avgResponseTime.ToString('F0'))ms" -ForegroundColor White
        Write-Host "Min Response Time: ${minResponseTime}ms" -ForegroundColor White
        Write-Host "Max Response Time: ${maxResponseTime}ms" -ForegroundColor White
        Write-Host "Throughput: $throughput requests/sec" -ForegroundColor White
        Write-Host "Successful Requests: $successfulRequests/$UserCount ($($successRate.ToString('P1')))" -ForegroundColor White
        Write-Host "Performance PASS: $performancePass" -ForegroundColor $(if ($performancePass) { "Green" } else { "Red" })
    }
    
    # CSV output (always output this)
    $csvResult = "$TestId,/directory/download,Concurrent download test,10 files 10MB,$UserCount,$UserCount,$(if ($performancePass) { 'PASS' } else { 'FAIL' }),$($avgResponseTime.ToString('F0')),$throughput,Min:${minResponseTime}ms Max:${maxResponseTime}ms Success:$successfulRequests/$UserCount"
    Write-Host "CSV_RESULT:$csvResult"
    
    return @{
        TestId = $TestId
        UserCount = $UserCount
        PerformancePass = $performancePass
        AvgResponseTime = $avgResponseTime
        Throughput = $throughput
        SuccessRate = $successRate
        CSVResult = $csvResult
    }
}

# Main execution
try {
    $envVars = Get-BrunoEnvironment -EnvName $Environment
    
    if (-not $OutputCSVOnly) {
        Write-Host "Running concurrent download tests with environment: $Environment" -ForegroundColor Green
        Write-Host "Base URL: $($envVars.baseUrl)" -ForegroundColor Gray
        Write-Host "Test configurations: $($ConcurrentUsers -join ', ') users" -ForegroundColor Gray
        Write-Host ""
    }
    
    $allResults = @()
    
    foreach ($userCount in $ConcurrentUsers) {
        $testId = switch ($userCount) {
            10 { "1.4a" }
            25 { "1.4b" }
            50 { "1.4c" }
            default { "1.4x" }
        }
        
        $result = Start-ConcurrentTest -UserCount $userCount -TestId $testId -EnvVars $envVars
        $allResults += $result
        
        # Brief pause between tests
        if ($userCount -ne $ConcurrentUsers[-1]) {
            Start-Sleep -Seconds 2
        }
    }
    
    if (-not $OutputCSVOnly) {
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Total concurrent tests: $($allResults.Count)" -ForegroundColor White
        Write-Host "Passed tests: $(($allResults | Where-Object { $_.PerformancePass }).Count)" -ForegroundColor Green
        Write-Host "Failed tests: $(($allResults | Where-Object { -not $_.PerformancePass }).Count)" -ForegroundColor Red
        
        Write-Host "`nTo integrate with Bruno CSV extraction:" -ForegroundColor Yellow
        Write-Host ".\concurrent-download-test.ps1 -Environment $Environment -OutputCSVOnly | Select-String 'CSV_RESULT:'" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Error running concurrent tests: $($_.Exception.Message)"
    exit 1
}
