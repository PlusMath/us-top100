$ErrorActionPreference = 'Continue'
$root = "C:\Users\h24795\claude\us-top100"
$scratch = "C:\Users\h24795\AppData\Local\Temp\claude\C--Users-h24795-claude\c1535995-6c4d-4f4b-8a76-027da4b137ea\scratchpad\data"
New-Item -ItemType Directory -Force -Path "$scratch\facts" | Out-Null
New-Item -ItemType Directory -Force -Path "$scratch\charts" | Out-Null

$cikText = [System.IO.File]::ReadAllText("$root\cik_map.json", [System.Text.Encoding]::UTF8)
$ciks = $cikText | ConvertFrom-Json

$ua = "PlusMath-us-top100-research contact@plusmath-project.example"
$skip = @('AAPL','MSFT')

$count = 0
foreach ($c in $ciks) {
  if ($skip -contains $c.ticker) { continue }
  $cikPadded = "{0:D10}" -f [int64]$c.cik
  $factsPath = "$scratch\facts\$($c.ticker)_facts.json"
  $chartPath = "$scratch\charts\$($c.ticker)_chart.json"

  if (-not (Test-Path $factsPath) -or (Get-Item $factsPath).Length -lt 1000) {
    try {
      Invoke-WebRequest -Uri "https://data.sec.gov/api/xbrl/companyfacts/CIK$cikPadded.json" -Headers @{ "User-Agent" = $ua } -OutFile $factsPath -TimeoutSec 30
      Write-Host "[facts] $($c.ticker) OK"
    } catch {
      Write-Host "[facts] $($c.ticker) FAILED: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 300
  }

  if (-not (Test-Path $chartPath) -or (Get-Item $chartPath).Length -lt 500) {
    try {
      Invoke-WebRequest -Uri "https://query1.finance.yahoo.com/v8/finance/chart/$($c.ticker)?range=1y&interval=1d" -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $chartPath -TimeoutSec 30
      Write-Host "[chart] $($c.ticker) OK"
    } catch {
      Write-Host "[chart] $($c.ticker) FAILED: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 300
  }

  $count++
}
Write-Host "DONE. Processed $count tickers."
