$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$jsonText = [System.IO.File]::ReadAllText((Join-Path $root 'stocks_data.json'), [System.Text.Encoding]::UTF8)
$stocks = $jsonText | ConvertFrom-Json

$template = [System.IO.File]::ReadAllText((Join-Path $root 'stub_template.html'), [System.Text.Encoding]::UTF8)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$count = 0

foreach ($s in $stocks) {
  if ($s.t -eq 'AAPL' -or $s.t -eq 'MSFT') { continue }

  $seed = 0
  foreach ($ch in $s.t.ToCharArray()) { $seed = ($seed * 31 + [int][char]$ch) % 90000 }
  $basePrice = 20 + ($seed % 550)
  $price = [math]::Round($basePrice * (1 + ($seed % 17) / 100.0), 2)
  $high = [math]::Round($price * 1.18, 2)
  $low = [math]::Round($price * 0.72, 2)
  $rev = [math]::Round($basePrice * 0.9 + ($seed % 40), 1)
  $oi = [math]::Round($rev * (0.15 + ($seed % 20) / 100.0), 1)
  $eps = [math]::Round(($price / (12 + ($seed % 20))), 2)

  $html = $template.
    Replace('__NAME__', $s.name).
    Replace('__TICKER__', $s.t).
    Replace('__IND__', $s.ind).
    Replace('__RANK__', [string]$s.rank).
    Replace('__PRICE__', [string]$price).
    Replace('__HIGH__', [string]$high).
    Replace('__LOW__', [string]$low).
    Replace('__REV__', [string]$rev).
    Replace('__OI__', [string]$oi).
    Replace('__EPS__', [string]$eps).
    Replace('__BASEPRICE__', [string]$basePrice)

  $rankStr = '{0:D3}' -f [int]$s.rank
  $outPath = Join-Path $root "stocks\$rankStr`_$($s.t).html"
  [System.IO.File]::WriteAllText($outPath, $html, $utf8NoBom)
  $count++
}

Write-Host "Generated $count stub pages."

$sb = New-Object System.Text.StringBuilder
foreach ($s in $stocks) {
  $rankStr = '{0:D3}' -f [int]$s.rank
  $page = "stocks/$rankStr`_$($s.t).html"
  [void]$sb.AppendLine("      { rank: $($s.rank), name: `"$($s.name)`", ticker: `"$($s.t)`", industry: `"$($s.ind)`", page: `"$page`" },")
}
[System.IO.File]::WriteAllText((Join-Path $root 'stocks_data.js.txt'), $sb.ToString(), $utf8NoBom)
Write-Host "Wrote stocks_data.js.txt"
