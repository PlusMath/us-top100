$ErrorActionPreference = 'Continue'
$root = "C:\Users\h24795\claude\us-top100"
$scratch = "C:\Users\h24795\AppData\Local\Temp\claude\C--Users-h24795-claude\c1535995-6c4d-4f4b-8a76-027da4b137ea\scratchpad\data"

$cikText = [System.IO.File]::ReadAllText("$root\cik_map.json", [System.Text.Encoding]::UTF8)
$ciks = $cikText | ConvertFrom-Json
$skip = @('AAPL','MSFT')

# Extract the JSON object value for "key":{ ... } from raw text via brace matching (avoids
# ConvertFrom-Json's case-insensitive-duplicate-key crash on the full multi-MB file).
function Extract-JsonObjectFor([string]$rawText, [string]$key) {
  $needle = '"' + $key + '":{'
  $idx = $rawText.IndexOf($needle)
  if ($idx -lt 0) { return $null }
  $start = $idx + $needle.Length - 1  # position of opening brace
  $depth = 0
  $inStr = $false
  $esc = $false
  for ($i = $start; $i -lt $rawText.Length; $i++) {
    $ch = $rawText[$i]
    if ($inStr) {
      if ($esc) { $esc = $false }
      elseif ($ch -eq '\') { $esc = $true }
      elseif ($ch -eq '"') { $inStr = $false }
      continue
    }
    if ($ch -eq '"') { $inStr = $true; continue }
    if ($ch -eq '{') { $depth++ }
    elseif ($ch -eq '}') {
      $depth--
      if ($depth -eq 0) {
        return $rawText.Substring($start, $i - $start + 1)
      }
    }
  }
  return $null
}

function Get-ConceptUnit([string]$rawText, [string]$concept, [string]$unit) {
  $objText = Extract-JsonObjectFor $rawText $concept
  if (-not $objText) { return $null }
  try {
    $obj = $objText | ConvertFrom-Json
  } catch { return $null }
  if (-not $obj.units) { return $null }
  $prop = $obj.units.PSObject.Properties[$unit]
  if (-not $prop) { return $null }
  return $prop.Value
}

function Get-Annual3($items) {
  if (-not $items) { return @() }
  $filtered = $items | Where-Object { $_.form -eq '10-K' -and $_.start -and $_.end }
  $withDur = @()
  foreach ($it in $filtered) {
    $s = [datetime]$it.start; $e = [datetime]$it.end
    $days = ($e - $s).Days
    if ($days -ge 340 -and $days -le 380) {
      $withDur += [PSCustomObject]@{ end=$it.end; start=$it.start; val=$it.val; filed=$it.filed; EndDate=$e }
    }
  }
  $dedup = $withDur | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  return ($dedup | Sort-Object EndDate -Descending | Select-Object -First 3)
}

function Get-LatestQuarter($items) {
  if (-not $items) { return $null }
  $filtered = $items | Where-Object { $_.form -eq '10-Q' -and $_.start -and $_.end }
  $withDur = @()
  foreach ($it in $filtered) {
    $s = [datetime]$it.start; $e = [datetime]$it.end
    $days = ($e - $s).Days
    if ($days -ge 75 -and $days -le 100) {
      $withDur += [PSCustomObject]@{ end=$it.end; start=$it.start; val=$it.val; filed=$it.filed; EndDate=$e }
    }
  }
  $dedup = $withDur | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  $sorted = $dedup | Sort-Object EndDate -Descending
  if ($sorted.Count -eq 0) { return $null }
  $latest = $sorted[0]
  $target = $latest.EndDate.AddDays(-365)
  $prior = $sorted | Where-Object { [math]::Abs(($_.EndDate - $target).Days) -le 20 } | Select-Object -First 1
  return @{ latest = $latest; prior = $prior }
}

function Get-LatestInstant($items, [string]$formFilter) {
  if (-not $items) { return $null }
  $filtered = if ($formFilter) { $items | Where-Object { $_.form -eq $formFilter } } else { $items }
  $dedup = $filtered | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  $sorted = $dedup | Sort-Object { [datetime]$_.end } -Descending
  if ($sorted.Count -eq 0) { return $null }
  return $sorted[0]
}

function Get-MaxRecentEndDate($items) {
  if (-not $items) { return $null }
  $dates = $items | Where-Object { $_.form -eq '10-K' -or $_.form -eq '10-Q' } | ForEach-Object { try { [datetime]$_.end } catch {} }
  if (-not $dates -or @($dates).Count -eq 0) { return $null }
  return ($dates | Sort-Object -Descending | Select-Object -First 1)
}

function Pick-ConceptItems([string]$rawText, [string[]]$names, [string]$unit) {
  # Some companies stop tagging an older concept and switch to a newer one,
  # leaving stale historical facts behind under the old tag (e.g. AVGO's
  # NetIncomeLoss stops in FY2024 while ProfitLoss continues into FY2025).
  # Evaluate every candidate concept and keep whichever has the globally
  # freshest data, rather than stopping at the first one that merely clears
  # an absolute staleness cutoff.
  $candidates = @()
  foreach ($n in $names) {
    $items = Get-ConceptUnit $rawText $n $unit
    if ($items -and $items.Count -gt 0) {
      $maxDate = Get-MaxRecentEndDate $items
      $candidates += @{ items = $items; concept = $n; maxDate = $maxDate }
    }
  }
  if ($candidates.Count -eq 0) { return $null }
  return ($candidates | Sort-Object { if ($_.maxDate) { $_.maxDate } else { [datetime]::MinValue } } -Descending | Select-Object -First 1)
}

function Analyze-Chart($chartData) {
  $res = $chartData.chart.result[0]
  if (-not $res) { return $null }
  $ts = $res.timestamp
  $q = $res.indicators.quote[0]
  $rows = @()
  for ($i = 0; $i -lt $ts.Count; $i++) {
    if ($null -eq $q.close[$i]) { continue }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($ts[$i]).UtcDateTime
    $rows += [PSCustomObject]@{ date=$dt; open=$q.open[$i]; high=$q.high[$i]; low=$q.low[$i]; close=$q.close[$i] }
  }
  $n = $rows.Count
  if ($n -lt 30) { return $null }
  $last = $rows[$n-1]; $prev = $rows[$n-2]
  $hiRow = $rows | Sort-Object high -Descending | Select-Object -First 1
  $loRow = $rows | Sort-Object low | Select-Object -First 1
  function MA($p) { ($rows[($n-$p)..($n-1)] | Measure-Object -Property close -Average).Average }
  $segSize = [math]::Ceiling($n/4)
  $segs = @()
  for ($s=0; $s -lt 4; $s++) {
    $start = $s*$segSize
    $end = [math]::Min($start+$segSize-1, $n-1)
    if ($start -gt $n-1) { continue }
    $slice = $rows[$start..$end]
    $segHigh = ($slice | Measure-Object -Property high -Maximum).Maximum
    $segLow = ($slice | Measure-Object -Property low -Minimum).Minimum
    $chg = [math]::Round((($slice[-1].close-$slice[0].close)/$slice[0].close)*100,2)
    $segs += [PSCustomObject]@{ startDate=$slice[0].date.ToString('yy.MM.dd'); endDate=$slice[-1].date.ToString('yy.MM.dd'); startClose=[math]::Round($slice[0].close,2); endClose=[math]::Round($slice[-1].close,2); chgPct=$chg; segHigh=[math]::Round($segHigh,2); segLow=[math]::Round($segLow,2) }
  }
  $dailyChg = [math]::Round((($last.close-$prev.close)/$prev.close)*100,2)
  return [PSCustomObject]@{
    price = [math]::Round($last.close,2)
    priceDate = $last.date.ToString('yyyy-MM-dd')
    dailyChgPct = $dailyChg
    hi52 = [math]::Round($hiRow.high,2); hi52Date = $hiRow.date.ToString('yy/MM/dd')
    lo52 = [math]::Round($loRow.low,2); lo52Date = $loRow.date.ToString('yy/MM/dd')
    ma5 = [math]::Round((MA 5),2); ma20 = [math]::Round((MA 20),2); ma60 = [math]::Round((MA 60),2); ma120 = [math]::Round((MA 120),2)
    segments = $segs
  }
}

$revConcepts = @('RevenueFromContractWithCustomerExcludingAssessedTax','Revenues','SalesRevenueNet')
$oiConcepts = @('OperatingIncomeLoss')
$preTaxConcepts = @('IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest','IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments')
$niConcepts = @('NetIncomeLoss','ProfitLoss')
$epsConcepts = @('EarningsPerShareDiluted')
$epsBasicConcepts = @('EarningsPerShareBasic')
$assetsConcepts = @('Assets')
$liabConcepts = @('Liabilities')
$equityConcepts = @('StockholdersEquity','StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest')
$divConcepts = @('CommonStockDividendsPerShareDeclared','CommonStockDividendsPerShareCashPaid')

$allMetrics = @()
$failed = @()

foreach ($c in $ciks) {
  if ($skip -contains $c.ticker) { continue }
  $t = $c.ticker
  $factsPath = "$scratch\facts\$t`_facts.json"
  $chartPath = "$scratch\charts\$t`_chart.json"
  if (-not (Test-Path $factsPath) -or -not (Test-Path $chartPath)) { $failed += "$t (missing file)"; continue }

  try {
    $rawText = [System.IO.File]::ReadAllText($factsPath, [System.Text.Encoding]::UTF8)
    $chartRaw = [System.IO.File]::ReadAllText($chartPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    $failed += "$t (read error: $($_.Exception.Message))"
    continue
  }

  $revPick = Pick-ConceptItems $rawText $revConcepts 'USD'
  $oiPick = Pick-ConceptItems $rawText $oiConcepts 'USD'
  $usedPreTax = $false
  if (-not $oiPick) { $oiPick = Pick-ConceptItems $rawText $preTaxConcepts 'USD'; if ($oiPick) { $usedPreTax = $true } }
  $niPick = Pick-ConceptItems $rawText $niConcepts 'USD'
  $epsPick = Pick-ConceptItems $rawText $epsConcepts 'USD/shares'
  if (-not $epsPick) { $epsPick = Pick-ConceptItems $rawText $epsBasicConcepts 'USD/shares' }
  $assetsPick = Pick-ConceptItems $rawText $assetsConcepts 'USD'
  $liabPick = Pick-ConceptItems $rawText $liabConcepts 'USD'
  $equityPick = Pick-ConceptItems $rawText $equityConcepts 'USD'
  $divPick = Pick-ConceptItems $rawText $divConcepts 'USD/shares'

  $revAnnual = Get-Annual3 $revPick.items
  $oiAnnual = Get-Annual3 $oiPick.items
  $niAnnual = Get-Annual3 $niPick.items
  $epsAnnual = Get-Annual3 $epsPick.items

  $revQ = Get-LatestQuarter $revPick.items
  $oiQ = Get-LatestQuarter $oiPick.items
  $niQ = Get-LatestQuarter $niPick.items
  $epsQ = Get-LatestQuarter $epsPick.items

  $assetsFY = Get-LatestInstant $assetsPick.items '10-K'
  $liabFY = Get-LatestInstant $liabPick.items '10-K'
  $equityFY = Get-LatestInstant $equityPick.items '10-K'
  $assetsLatest = Get-LatestInstant $assetsPick.items $null
  $liabLatest = Get-LatestInstant $liabPick.items $null
  $equityLatest = Get-LatestInstant $equityPick.items $null

  $divAnnual = Get-Annual3 $divPick.items
  $divQ = Get-LatestQuarter $divPick.items

  $sharesOut = $null
  $deiItems = Get-ConceptUnit $rawText 'EntityCommonStockSharesOutstanding' 'shares'
  if ($deiItems) {
    $sorted = $deiItems | Sort-Object { [datetime]$_.end } -Descending
    if ($sorted.Count -gt 0) { $sharesOut = $sorted[0].val }
  }

  $chartAnalysis = Analyze-Chart $chartRaw

  $metric = [PSCustomObject]@{
    ticker = $t
    cik = $c.cik
    revConcept = $revPick.concept
    oiConcept = $oiPick.concept
    oiIsPreTax = $usedPreTax
    revAnnual = @($revAnnual | ForEach-Object { [PSCustomObject]@{ end=$_.end; start=$_.start; val=$_.val } })
    oiAnnual = @($oiAnnual | ForEach-Object { [PSCustomObject]@{ end=$_.end; start=$_.start; val=$_.val } })
    niAnnual = @($niAnnual | ForEach-Object { [PSCustomObject]@{ end=$_.end; start=$_.start; val=$_.val } })
    epsAnnual = @($epsAnnual | ForEach-Object { [PSCustomObject]@{ end=$_.end; start=$_.start; val=$_.val } })
    revQLatest = if ($revQ) { $revQ.latest.val } else { $null }
    revQPrior = if ($revQ -and $revQ.prior) { $revQ.prior.val } else { $null }
    revQEnd = if ($revQ) { $revQ.latest.end } else { $null }
    revQStart = if ($revQ) { $revQ.latest.start } else { $null }
    oiQLatest = if ($oiQ) { $oiQ.latest.val } else { $null }
    oiQPrior = if ($oiQ -and $oiQ.prior) { $oiQ.prior.val } else { $null }
    niQLatest = if ($niQ) { $niQ.latest.val } else { $null }
    niQPrior = if ($niQ -and $niQ.prior) { $niQ.prior.val } else { $null }
    epsQLatest = if ($epsQ) { $epsQ.latest.val } else { $null }
    epsQPrior = if ($epsQ -and $epsQ.prior) { $epsQ.prior.val } else { $null }
    assetsFY = if ($assetsFY) { $assetsFY.val } else { $null }
    assetsFYEnd = if ($assetsFY) { $assetsFY.end } else { $null }
    liabFY = if ($liabFY) { $liabFY.val } else { $null }
    equityFY = if ($equityFY) { $equityFY.val } else { $null }
    assetsLatest = if ($assetsLatest) { $assetsLatest.val } else { $null }
    assetsLatestEnd = if ($assetsLatest) { $assetsLatest.end } else { $null }
    liabLatest = if ($liabLatest) { $liabLatest.val } else { $null }
    equityLatest = if ($equityLatest) { $equityLatest.val } else { $null }
    divAnnualLatest = if ($divAnnual.Count -gt 0) { $divAnnual[0].val } else { $null }
    divQLatest = if ($divQ) { $divQ.latest.val } else { $null }
    sharesOut = $sharesOut
    chart = $chartAnalysis
  }
  $allMetrics += $metric
}

$json = $allMetrics | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText("$root\all_metrics.json", $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote all_metrics.json with $($allMetrics.Count) companies."
if ($failed.Count -gt 0) {
  Write-Host "FAILED/INCOMPLETE ($($failed.Count)):"
  $failed | ForEach-Object { Write-Host "  $_" }
}
