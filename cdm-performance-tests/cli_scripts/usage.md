# Test the setup
.\ci_scripts\test-concurrent-setup.ps1 -Environment local

# Run basic tests only
.\ci_scripts\extract-csv-results-concurrent.ps1 -Environment local

# Run with concurrent testing (10, 25, 50 users)
.\ci_scripts\extract-csv-results-concurrent.ps1 -Environment local -IncludeConcurrent

# Custom concurrent test (5, 15, 30 users)
.\ci_scripts\concurrent-download-test.ps1 -Environment local -ConcurrentUsers @(5,15,30)
