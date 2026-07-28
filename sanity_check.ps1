$root = "C:\Users\h24795\claude\us-top100"
$m = [System.IO.File]::ReadAllText("$root\all_metrics.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$issues = 0
foreach ($item in $m) {
  $revA = @($item.revAnnual | Sort-Object { [datetime]$_.end })
  $oiA = @($item.oiAnnual | Sort-Object { [datetime]$_.end })
  $niA = @($item.niAnnual | Sort-Object { [datetime]$_.end })
  if ($revA.Count -gt 0 -and $oiA.Count -gt 0) {
    if ([double]$oiA[-1].val -gt [double]$revA[-1].val) {
      Write-Host "[OI>REV] $($item.ticker): oi=$($oiA[-1].val) rev=$($revA[-1].val)"
      $issues++
    }
  }
  if ($revA.Count -gt 0 -and $niA.Count -gt 0) {
    if ([double]$niA[-1].val -gt [double]$revA[-1].val) {
      Write-Host "[NI>REV] $($item.ticker): ni=$($niA[-1].val) rev=$($revA[-1].val)"
      $issues++
    }
  }
  if (-not $item.chart -or -not $item.chart.price) {
    Write-Host "[NO CHART] $($item.ticker)"
    $issues++
  }
  if ($revA.Count -eq 0 -and $niA.Count -eq 0) {
    Write-Host "[NO INCOME DATA] $($item.ticker)"
    $issues++
  }
}
Write-Host ""
Write-Host "Total issues: $issues / $($m.Count) companies"
