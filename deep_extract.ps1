$ErrorActionPreference = 'Continue'
$scratch = "C:\Users\h24795\AppData\Local\Temp\claude\C--Users-h24795-claude\c1535995-6c4d-4f4b-8a76-027da4b137ea\scratchpad\data"

function Extract-JsonObjectFor([string]$rawText, [string]$key) {
  $needle = '"' + $key + '":{'
  $idx = $rawText.IndexOf($needle)
  if ($idx -lt 0) { return $null }
  $start = $idx + $needle.Length - 1
  $depth = 0; $inStr = $false; $esc = $false
  for ($i = $start; $i -lt $rawText.Length; $i++) {
    $ch = $rawText[$i]
    if ($inStr) { if ($esc) { $esc=$false } elseif ($ch -eq '\') { $esc=$true } elseif ($ch -eq '"') { $inStr=$false }; continue }
    if ($ch -eq '"') { $inStr = $true; continue }
    if ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $rawText.Substring($start, $i-$start+1) } }
  }
  return $null
}
function Get-ConceptUnit([string]$rawText, [string]$concept, [string]$unit) {
  $objText = Extract-JsonObjectFor $rawText $concept
  if (-not $objText) { return $null }
  try { $obj = $objText | ConvertFrom-Json } catch { return $null }
  if (-not $obj.units) { return $null }
  $prop = $obj.units.PSObject.Properties[$unit]
  if (-not $prop) { return $null }
  return $prop.Value
}
function Get-Annual5($items) {
  if (-not $items) { return @() }
  $filtered = $items | Where-Object { $_.form -eq '10-K' -and $_.start -and $_.end }
  $withDur = @()
  foreach ($it in $filtered) {
    $s=[datetime]$it.start; $e=[datetime]$it.end; $days=($e-$s).Days
    if ($days -ge 340 -and $days -le 380) { $withDur += [PSCustomObject]@{end=$it.end;start=$it.start;val=$it.val;filed=$it.filed;EndDate=$e} }
  }
  $dedup = $withDur | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  return @($dedup | Sort-Object EndDate -Descending | Select-Object -First 5)
}
function Get-Quarters8($items) {
  if (-not $items) { return @() }
  $filtered = $items | Where-Object { $_.form -eq '10-Q' -and $_.start -and $_.end }
  $withDur = @()
  foreach ($it in $filtered) {
    $s=[datetime]$it.start; $e=[datetime]$it.end; $days=($e-$s).Days
    if ($days -ge 75 -and $days -le 100) { $withDur += [PSCustomObject]@{end=$it.end;start=$it.start;val=$it.val;filed=$it.filed;EndDate=$e} }
  }
  $dedup = $withDur | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  return @($dedup | Sort-Object EndDate -Descending | Select-Object -First 8)
}
function Get-LatestInstant2($items, $formFilter) {
  if (-not $items) { return $null }
  $f = if ($formFilter) { $items | Where-Object { $_.form -eq $formFilter } } else { $items }
  $dedup = $f | Group-Object end | ForEach-Object { $_.Group | Sort-Object filed -Descending | Select-Object -First 1 }
  $sorted = $dedup | Sort-Object { [datetime]$_.end } -Descending
  if ($sorted.Count -eq 0) { return $null }
  return $sorted[0]
}

$tickers = @(
  @{t='META'; f="$scratch\facts\META_facts.json"},
  @{t='AVGO'; f="$scratch\facts\AVGO_facts.json"},
  @{t='TSLA'; f="$scratch\facts\TSLA_facts.json"},
  @{t='BRKB'; f="$scratch\facts\BRKB_facts.json"},
  @{t='JPM'; f="$scratch\facts\JPM_facts.json"}
)

$ocfNames = @('NetCashProvidedByUsedInOperatingActivities','NetCashProvidedByUsedInOperatingActivitiesContinuingOperations')
$capexNames = @('PaymentsToAcquirePropertyPlantAndEquipment','PaymentsToAcquireProductiveAssets')
$buybackNames = @('PaymentsForRepurchaseOfCommonStock','PaymentsForRepurchaseOfCapitalStock')
$cashNames = @('CashAndCashEquivalentsAtCarryingValue','CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents')
$debtNames = @('LongTermDebtNoncurrent','LongTermDebt')
$revNames = @('RevenueFromContractWithCustomerExcludingAssessedTax','Revenues')
$epsNames = @('EarningsPerShareDiluted')

$results = @{}
foreach ($tk in $tickers) {
  $raw = [System.IO.File]::ReadAllText($tk.f, [System.Text.Encoding]::UTF8)
  function TryConcepts($names, $unit) {
    $candidates = @()
    foreach ($n in $names) {
      $items = Get-ConceptUnit $raw $n $unit
      if ($items -and $items.Count -gt 0) {
        $dates = $items | Where-Object { $_.form -eq '10-K' -or $_.form -eq '10-Q' } | ForEach-Object { try { [datetime]$_.end } catch {} }
        $maxDate = if ($dates) { $dates | Sort-Object -Descending | Select-Object -First 1 } else { $null }
        $candidates += @{items=$items;concept=$n;maxDate=$maxDate}
      }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object { if ($_.maxDate) { $_.maxDate } else { [datetime]::MinValue } } -Descending | Select-Object -First 1)
  }
  $ocf = TryConcepts $ocfNames 'USD'
  $capex = TryConcepts $capexNames 'USD'
  $buyback = TryConcepts $buybackNames 'USD'
  $cash = TryConcepts $cashNames 'USD'
  $debt = TryConcepts $debtNames 'USD'
  $rev = TryConcepts ($revNames + @('SalesRevenueNet','InterestAndDividendIncomeOperating','Revenues')) 'USD'
  $eps = TryConcepts $epsNames 'USD/shares'
  $oi = TryConcepts @('OperatingIncomeLoss','IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest','IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments') 'USD'
  $ni = TryConcepts @('NetIncomeLoss','ProfitLoss') 'USD'

  Write-Host "=================== $($tk.t) ==================="
  Write-Host "-- Operating Cash Flow (5yr) [$($ocf.concept)] --"
  Get-Annual5 $ocf.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- CapEx (5yr) [$($capex.concept)] --"
  Get-Annual5 $capex.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- Buybacks (5yr) [$($buyback.concept)] --"
  Get-Annual5 $buyback.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- Cash (latest) [$($cash.concept)] --"
  $c = Get-LatestInstant2 $cash.items $null
  if ($c) { Write-Host "  $($c.end): $($c.val)" }
  Write-Host "-- LT Debt (latest) [$($debt.concept)] --"
  $d = Get-LatestInstant2 $debt.items $null
  if ($d) { Write-Host "  $($d.end): $($d.val)" }
  Write-Host "-- Revenue 5yr [$($rev.concept)] --"
  Get-Annual5 $rev.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- Operating Income 5yr --"
  Get-Annual5 $oi.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- Net Income 5yr --"
  Get-Annual5 $ni.items | ForEach-Object { Write-Host "  $($_.end): $($_.val)" }
  Write-Host "-- EPS diluted last 8 quarters --"
  Get-Quarters8 $eps.items | ForEach-Object { Write-Host "  $($_.start) to $($_.end): $($_.val)" }
  Write-Host "-- Free Cash Flow (OCF - CapEx) 5yr --"
  $ocf5 = Get-Annual5 $ocf.items
  $capex5 = Get-Annual5 $capex.items
  foreach ($o in $ocf5) {
    $matching = $capex5 | Where-Object { $_.end -eq $o.end }
    if ($matching) { Write-Host ("  {0}: FCF={1}" -f $o.end, ([double]$o.val - [double]$matching[0].val)) }
  }
  Write-Host ""
}
