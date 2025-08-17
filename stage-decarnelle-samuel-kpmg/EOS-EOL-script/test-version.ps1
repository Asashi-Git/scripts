# Simple script to check version formats in Excel file
Import-Module ImportExcel -ErrorAction Stop
$data = Import-Excel -Path 'MDE_AllDevices_20250625.xlsx' -StartRow 1 -EndRow 10

Write-Host "Columns available:" -ForegroundColor Green
$data[0].PSObject.Properties.Name | Sort-Object | ForEach-Object { Write-Host "  - $_" }

Write-Host "`nSample data (first 5 rows):" -ForegroundColor Green
for ($i = 0; $i -lt 5 -and $i -lt $data.Count; $i++) {
    $row = $data[$i]
    Write-Host "Row $($i+1):"
    Write-Host "  osPlatform: $($row.osPlatform)"
    
    # Check all possible version columns
    $versionColumns = @("version", "Version", "osVersion", "OSVersion", "osVersionInfo", "OSVersionInfo")
    foreach ($col in $versionColumns) {
        if ($row.PSObject.Properties.Name -contains $col) {
            $value = $row.$col
            Write-Host "  ${col}: $value"
        }
    }
    Write-Host ""
}
