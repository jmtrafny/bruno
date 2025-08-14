param(
    [string]$Environment = "local",
    [int[]]$ConcurrentUsers = @(10, 25, 50),
    [switch]$OutputCSVOnly = $false
)

# Load environment variables from Bruno environment file
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
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq "vars {") {
            $inVarsSection = $true
            continue
        }
        if ($trimmedLine -eq "}") {
            $inVarsSection = $false
            continue
        }
        if ($inVarsSection -and $trimmedLine.Contains(":")) {
            $parts = $trimmedLine.Split(":", 2)
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()
                $envVars[$key] = $value
            }
        }
    }
    
    return $envVars
}

# Run concurrent test
function Start-ConcurrentTest {
    param(
        [int]$UserCount,
        [string]$TestId,
        [hashtable]$EnvVars
    )
    
    if (-not $OutputCSVOnly) {
        Write-Host "`nStarting Test $TestId - $UserCount Concurrent Users" -ForegroundColor Cyan
    }
    
    $startTime = Get-Date
    
    # Create concurrent jobs
    $jobs = @()
    for ($i = 1; $i -le $UserCount; $i++) {
        $job = Start-Job -ScriptBlock {
            param($BaseUrl, $TestBucket, $ScratchPath, $RequestId, $TestId)
            
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
                    
                    $httpStatus = 0
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                        $httpStatus = [int]$_.Exception.Response.StatusCode
                    }
                    
                    return @{
                        Success = $false
                        ResponseTime = [int]$responseTime
                        HttpStatus = $httpStatus
                        ApiStatus = "ERROR"
                        FileCount = 0
                        Error = $_.Exception.Message
                    }
                }
            }
            
            Invoke-DownloadRequest -BaseUrl $BaseUrl -TestBucket $TestBucket -ScratchPath $ScratchPath -RequestId $RequestId -TestId $TestId
        } -ArgumentList $EnvVars.baseUrl, $EnvVars.testBucket, $EnvVars.scratchPath, $i, $TestId
        
        $jobs += $job
    }
    
    # Wait for all jobs to complete
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
        Write-Host "Average Response Time: $($avgResponseTime.ToString('F0'))ms" -ForegroundColor White
        Write-Host "Throughput: $throughput requests/sec" -ForegroundColor White
        Write-Host "Successful: $successfulRequests/$UserCount" -ForegroundColor White
        Write-Host "Performance PASS: $performancePass" -ForegroundColor $(if ($performancePass) { "Green" } else { "Red" })
    }
    
    # CSV output
    $csvResult = "$TestId,/directory/download,Concurrent download test,10 files 10MB,$UserCount,$UserCount,$(if ($performancePass) { 'PASS' } else { 'FAIL' }),$($avgResponseTime.ToString('F0')),$throughput,Min:${minResponseTime}ms Max:${maxResponseTime}ms Success:$successfulRequests/$UserCount"
    Write-Host "CSV_RESULT:$csvResult"
    
    return @{
        TestId = $TestId
        UserCount = $UserCount
        PerformancePass = $performancePass
        AvgResponseTime = $avgResponseTime
        Throughput = $throughput
        SuccessRate = $successRate
    }
}

# Main execution
try {
    $envVars = Get-BrunoEnvironment -EnvName $Environment
    
    if (-not $OutputCSVOnly) {
        Write-Host "Running concurrent tests with environment: $Environment" -ForegroundColor Green
        Write-Host "Base URL: $($envVars.baseUrl)" -ForegroundColor Gray
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
        Write-Host "`nSummary: $($allResults.Count) tests completed" -ForegroundColor Cyan
        $passedTests = ($allResults | Where-Object { $_.PerformancePass }).Count
        Write-Host "Passed: $passedTests/$($allResults.Count)" -ForegroundColor Green
    }
}
catch {
    Write-Error "Error running concurrent tests: $($_.Exception.Message)"
    exit 1
}