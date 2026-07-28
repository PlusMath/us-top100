$ErrorActionPreference = 'Continue'
$root = "C:\Users\h24795\claude\us-top100"
$scratch = "C:\Users\h24795\AppData\Local\Temp\claude\C--Users-h24795-claude\c1535995-6c4d-4f4b-8a76-027da4b137ea\scratchpad\data"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$stocksText = [System.IO.File]::ReadAllText("$root\stocks_data.json", [System.Text.Encoding]::UTF8)
$stocks = $stocksText | ConvertFrom-Json
$metricsText = [System.IO.File]::ReadAllText("$root\all_metrics.json", [System.Text.Encoding]::UTF8)
$metrics = $metricsText | ConvertFrom-Json
$metricsByTicker = @{}
foreach ($m in $metrics) { $metricsByTicker[$m.ticker] = $m }

function Fmt-USD($val) {
  if ($null -eq $val) { return $null }
  $v = [double]$val
  $abs = [math]::Abs($v)
  if ($abs -ge 1e12) { return "`${0:N2}T" -f ($v/1e12) }
  elseif ($abs -ge 1e9) { return "`${0:N2}B" -f ($v/1e9) }
  elseif ($abs -ge 1e6) { return "`${0:N1}M" -f ($v/1e6) }
  else { return "`${0:N0}" -f $v }
}
function Fmt-USD0($val) {
  if ($null -eq $val) { return $null }
  $v = [double]$val
  $abs = [math]::Abs($v)
  if ($abs -ge 1e12) { return "`${0:N1}T" -f ($v/1e12) }
  elseif ($abs -ge 1e9) { return "`${0:N0}B" -f ($v/1e9) }
  elseif ($abs -ge 1e6) { return "`${0:N0}M" -f ($v/1e6) }
  else { return "`${0:N0}" -f $v }
}
function Pct($new,$old) {
  if ($null -eq $new -or $null -eq $old -or $old -eq 0) { return $null }
  return [math]::Round((([double]$new-[double]$old)/[math]::Abs([double]$old))*100,1)
}
function PctStr($p) {
  if ($null -eq $p) { return "N/A" }
  $sign = if ($p -ge 0) { "+" } else { "" }
  return "$sign$p%"
}
function ArrowPctSpan($p, [switch]$asIs) {
  if ($null -eq $p) { return "" }
  $cls = if ($p -ge 0) { "up" } else { "dn" }
  $arrow = if ($p -ge 0) { "&#9650;" } else { "&#9660;" }
  return "<span class=`"$cls`">$arrow$([math]::Abs($p))%</span>"
}
function Ev-Growth($p) {
  if ($null -eq $p) { return @{cls='ev-3'; label='정보없음'} }
  if ($p -lt 0) { return @{cls='ev-1'; label='감소'} }
  if ($p -lt 5) { return @{cls='ev-3'; label='적정'} }
  if ($p -lt 15) { return @{cls='ev-4'; label='높음'} }
  return @{cls='ev-5'; label='매우높음'}
}
function Ev-PER($per) {
  if ($null -eq $per -or $per -le 0) { return @{cls='ev-3'; label='산출불가'} }
  if ($per -lt 15) { return @{cls='ev-1'; label='1단계'} }
  if ($per -lt 25) { return @{cls='ev-3'; label='3단계'} }
  if ($per -lt 35) { return @{cls='ev-4'; label='4단계'} }
  return @{cls='ev-5'; label='5단계'}
}
function Ev-PBR($pbr) {
  if ($null -eq $pbr -or $pbr -le 0) { return @{cls='ev-3'; label='산출불가'} }
  if ($pbr -lt 1.5) { return @{cls='ev-1'; label='1단계'} }
  if ($pbr -lt 4) { return @{cls='ev-3'; label='3단계'} }
  if ($pbr -lt 8) { return @{cls='ev-4'; label='4단계'} }
  return @{cls='ev-5'; label='5단계'}
}
function Ev-Yield($y) {
  if ($null -eq $y) { return @{cls='ev-3'; label='배당없음'} }
  if ($y -lt 0.5) { return @{cls='ev-3'; label='3단계'} }
  if ($y -lt 2.5) { return @{cls='ev-2'; label='2단계'} }
  if ($y -lt 4.5) { return @{cls='ev-2'; label='2단계'} }
  return @{cls='ev-4'; label='4단계'}
}

function Build-CandleJs($chartPath) {
  $raw = [System.IO.File]::ReadAllText($chartPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  $res = $raw.chart.result[0]
  if (-not $res) { return $null }
  $ts = $res.timestamp
  $q = $res.indicators.quote[0]
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('[')
  for ($i=0; $i -lt $ts.Count; $i++) {
    if ($null -eq $q.close[$i]) { continue }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($ts[$i]).UtcDateTime.ToString('yyyy-MM-dd')
    $o = [math]::Round($q.open[$i],2); $h=[math]::Round($q.high[$i],2); $l=[math]::Round($q.low[$i],2); $c=[math]::Round($q.close[$i],2)
    [void]$sb.Append("{d:'$dt',o:$o,h:$h,l:$l,c:$c},")
  }
  [void]$sb.Append(']')
  return ($sb.ToString() -replace ',\]',']')
}

function Seg-Style($chg) {
  if ($chg -ge 5) { return @{bg='var(--color-background-success)'; fg='var(--color-text-success)'} }
  elseif ($chg -ge 0) { return @{bg='var(--color-background-secondary)'; fg='var(--color-text-secondary)'} }
  elseif ($chg -ge -8) { return @{bg='var(--color-background-warning)'; fg='var(--color-text-warning)'} }
  else { return @{bg='var(--color-background-danger)'; fg='var(--color-text-danger)'} }
}

$generated = 0
$skippedList = @()

foreach ($s in $stocks) {
  $t = $s.t
  # Hand-crafted flagship pages — never overwrite these with the generic template.
  $flagshipTickers = @('AAPL','MSFT','NVDA','GOOGL','AMZN','META','AVGO','TSLA','BRKB','JPM')
  if ($flagshipTickers -contains $t) { continue }
  $m = $metricsByTicker[$t]
  $chartPath = "$scratch\charts\$t`_chart.json"
  if (-not $m -or -not $m.chart -or -not (Test-Path $chartPath)) { $skippedList += $t; continue }

  $ch = $m.chart
  $price = $ch.price
  $shares = $m.sharesOut
  $mktCap = if ($shares) { [double]$price * [double]$shares } else { $null }

  # Annual arrays sorted ascending by end date (oldest first), up to 3
  $revA = @(); if ($m.revAnnual) { $revA = @($m.revAnnual | Sort-Object { [datetime]$_.end }) }
  $oiA = @(); if ($m.oiAnnual) { $oiA = @($m.oiAnnual | Sort-Object { [datetime]$_.end }) }
  $niA = @(); if ($m.niAnnual) { $niA = @($m.niAnnual | Sort-Object { [datetime]$_.end }) }
  $epsA = @(); if ($m.epsAnnual) { $epsA = @($m.epsAnnual | Sort-Object { [datetime]$_.end }) }

  $latestFYEnd = if ($niA.Count -gt 0) { $niA[-1].end } else { $null }
  $fyLabel = if ($latestFYEnd) { ([datetime]$latestFYEnd).ToString('yyyy') } else { '' }

  # Defensive sanity check: revenue/OI/EPS must be for the same fiscal period as NI
  # (a stale/mismatched concept can otherwise slip through, e.g. OI exceeding revenue).
  if ($revA.Count -gt 0 -and $latestFYEnd) {
    $revEndDiff = [math]::Abs((([datetime]$revA[-1].end) - ([datetime]$latestFYEnd)).Days)
    if ($revEndDiff -gt 45) { $revA = @() }
  }
  if ($revA.Count -gt 0 -and $oiA.Count -gt 0 -and [double]$oiA[-1].val -gt [double]$revA[-1].val) { $revA = @() }
  if ($oiA.Count -gt 0 -and $latestFYEnd) {
    $oiEndDiff = [math]::Abs((([datetime]$oiA[-1].end) - ([datetime]$latestFYEnd)).Days)
    if ($oiEndDiff -gt 45) { $oiA = @() }
  }
  if ($epsA.Count -gt 0 -and $latestFYEnd) {
    $epsEndDiff = [math]::Abs((([datetime]$epsA[-1].end) - ([datetime]$latestFYEnd)).Days)
    if ($epsEndDiff -gt 45) { $epsA = @() }
  }

  $revGrowthYoY = if ($revA.Count -ge 2) { Pct $revA[-1].val $revA[-2].val } else { $null }
  $oiGrowthYoY = if ($oiA.Count -ge 2) { Pct $oiA[-1].val $oiA[-2].val } else { $null }
  $niGrowthYoY = if ($niA.Count -ge 2) { Pct $niA[-1].val $niA[-2].val } else { $null }
  $epsGrowthYoY = if ($epsA.Count -ge 2) { Pct $epsA[-1].val $epsA[-2].val } else { $null }

  $revQYoY = Pct $m.revQLatest $m.revQPrior
  $oiQYoY = Pct $m.oiQLatest $m.oiQPrior
  $niQYoY = Pct $m.niQLatest $m.niQPrior
  $epsQYoY = Pct $m.epsQLatest $m.epsQPrior

  $latestEPS = if ($epsA.Count -gt 0) { [double]$epsA[-1].val } else { $null }
  $per = if ($latestEPS -and $latestEPS -gt 0) { [math]::Round($price / $latestEPS, 2) } else { $null }
  $epsQAnnualized = if ($m.epsQLatest) { [double]$m.epsQLatest * 4 } else { $null }
  $fwdPer = if ($epsQAnnualized -and $epsQAnnualized -gt 0) { [math]::Round($price / $epsQAnnualized, 2) } else { $null }

  $equityForBPS = if ($m.equityLatest) { [double]$m.equityLatest } else { $m.equityFY }
  $bps = if ($equityForBPS -and $shares) { [math]::Round($equityForBPS / [double]$shares, 2) } else { $null }
  $pbr = if ($bps -and $bps -gt 0) { [math]::Round($price / $bps, 2) } else { $null }

  $divQAnnualized = if ($m.divQLatest) { [double]$m.divQLatest * 4 } else { $null }
  $divYield = if ($divQAnnualized -and $price -gt 0) { [math]::Round($divQAnnualized / $price * 100, 2) } else { $null }
  $payoutRatio = if ($m.divAnnualLatest -and $latestEPS -and $latestEPS -gt 0) { [math]::Round([double]$m.divAnnualLatest / $latestEPS * 100, 1) } else { $null }

  $hcPct = Pct $price $ch.hi52
  $lcPct = Pct $price $ch.lo52

  $revEv = Ev-Growth $revGrowthYoY
  $niEv = Ev-Growth $niGrowthYoY
  $epsEv = Ev-Growth $epsGrowthYoY
  $niQEv = Ev-Growth $niQYoY
  $epsQEv = Ev-Growth $epsQYoY
  $perEv = Ev-PER $per
  $pbrEv = Ev-PBR $pbr
  $yieldEv = Ev-Yield $divYield

  # ---- header/summary text ----
  $oiLabel = if ($m.oiIsPreTax) { '세전이익' } else { '영업이익' }
  $revLine = if ($revA.Count -gt 0) { Fmt-USD0 $revA[-1].val } else { $null }
  $niLine = if ($niA.Count -gt 0) { Fmt-USD0 $niA[-1].val } else { $null }
  $oiLine = if ($oiA.Count -gt 0) { Fmt-USD0 $oiA[-1].val } else { $null }

  $trendBadge = if ($hcPct -ne $null -and $hcPct -ge -3) { '52주 고점권' }
    elseif ($lcPct -ne $null -and $lcPct -le 5) { '52주 저점권' }
    elseif ($price -gt $ch.ma20 -and $price -gt $ch.ma60) { '중기 상승추세' }
    elseif ($price -lt $ch.ma60 -and $price -lt $ch.ma120) { '중기 조정추세' }
    else { '박스권 등락' }

  $keyInsight = @()
  if ($niGrowthYoY -ne $null) {
    if ($niGrowthYoY -ge 10) { $keyInsight += "최근 회계연도 순이익이 전년比 $(PctStr $niGrowthYoY) 증가하며 이익 성장세" }
    elseif ($niGrowthYoY -ge 0) { $keyInsight += "최근 회계연도 순이익이 전년比 $(PctStr $niGrowthYoY)로 소폭 성장" }
    else { $keyInsight += "최근 회계연도 순이익이 전년比 $(PctStr $niGrowthYoY)로 감소" }
  }
  if ($niQYoY -ne $null) {
    if ($niQYoY -ge 10) { $keyInsight += "최근 분기 순이익은 전년동기比 $(PctStr $niQYoY)로 가속" }
    elseif ($niQYoY -ge 0) { $keyInsight += "최근 분기 순이익은 전년동기比 $(PctStr $niQYoY)" }
    else { $keyInsight += "최근 분기 순이익은 전년동기比 $(PctStr $niQYoY)로 둔화" }
  }
  if ($hcPct -ne $null) {
    if ($hcPct -ge -3) { $keyInsight += "주가는 52주 고점 부근($(PctStr $hcPct))에서 거래" }
    elseif ($hcPct -le -20) { $keyInsight += "주가는 52주 고점 대비 $(PctStr $hcPct) 조정된 상태" }
  }
  $keyInsightText = ($keyInsight -join '. ') + '.'

  # ---- bull/bear rule-based points ----
  $bulls = @()
  $bears = @()
  if ($niGrowthYoY -ne $null -and $niGrowthYoY -ge 10) { $bulls += @{t="최근 회계연도 순이익 $(PctStr $niGrowthYoY) 성장"; b='실적 모멘텀'} }
  if ($niQYoY -ne $null -and $niQYoY -ge 10) { $bulls += @{t="최근 분기 순이익 전년동기比 $(PctStr $niQYoY)"; b='이익 가속'} }
  if ($revGrowthYoY -ne $null -and $revGrowthYoY -ge 10) { $bulls += @{t="최근 회계연도 매출 $(PctStr $revGrowthYoY) 성장"; b='매출 성장'} }
  if ($lcPct -ne $null -and $lcPct -ge 30) { $bulls += @{t="52주 저점 대비 $(PctStr $lcPct) 상승"; b='중장기 강세'} }
  if ($price -gt $ch.ma20 -and $price -gt $ch.ma60 -and $price -gt $ch.ma120) { $bulls += @{t="5·20·60·120일선 모두 상회"; b='기술적 강세'} }
  if ($divYield -ne $null -and $divYield -ge 1.5 -and $payoutRatio -ne $null -and $payoutRatio -lt 60) { $bulls += @{t="배당수익률 $divYield% · 배당성향 $payoutRatio%로 안정적"; b='배당 매력'} }
  if ($per -ne $null -and $per -lt 20 -and $per -gt 0) { $bulls += @{t="트레일링 PER $($per)x로 상대적 저평가 구간"; b='밸류 매력'} }
  if ($bulls.Count -eq 0) { $bulls += @{t="안정적인 재무구조 유지"; b='재무 안정성'} }

  if ($per -ne $null -and $per -ge 30) { $bears += @{t="트레일링 PER $($per)x — 높은 밸류에이션 부담"; b='밸류 부담'} }
  if ($pbr -ne $null -and $pbr -ge 6) { $bears += @{t="PBR $($pbr)x — 자산가치 대비 높은 프리미엄"; b='밸류 부담'} }
  if ($niGrowthYoY -ne $null -and $niGrowthYoY -lt 0) { $bears += @{t="최근 회계연도 순이익 $(PctStr $niGrowthYoY)로 감소"; b='이익 둔화'} }
  if ($niQYoY -ne $null -and $niQYoY -lt 0) { $bears += @{t="최근 분기 순이익 전년동기比 $(PctStr $niQYoY)로 둔화"; b='단기 둔화'} }
  if ($hcPct -ne $null -and $hcPct -le -20) { $bears += @{t="52주 고점 대비 $(PctStr $hcPct) 조정 지속"; b='기술적 약세'} }
  if ($price -lt $ch.ma60 -and $price -lt $ch.ma120) { $bears += @{t="60·120일 이동평균선 하회 — 중기 추세 약세"; b='기술적 약세'} }
  if ($divYield -eq $null) { $bears += @{t="배당 미지급 — 인컴 매력 없음"; b='배당 없음'} }
  if ($bears.Count -eq 0) { $bears += @{t="뚜렷한 단기 리스크 요인은 제한적"; b='리스크 제한적'} }

  # ---- segments html ----
  $segLabels = @('구간 1','구간 2','구간 3','구간 4')
  $segHtml = New-Object System.Text.StringBuilder
  for ($i=0; $i -lt $ch.segments.Count; $i++) {
    $sg = $ch.segments[$i]
    $st = Seg-Style $sg.chgPct
    $sign = if ($sg.chgPct -ge 0) { '+' } else { '' }
    [void]$segHtml.Append("<div style=`"background:$($st.bg);border-radius:var(--border-radius-md);padding:9px 11px;`"><div style=`"color:$($st.fg);font-weight:600;margin-bottom:3px;`">$($segLabels[$i]) ($($sg.startDate)~$($sg.endDate))</div><div style=`"color:$($st.fg);line-height:1.6;`">`$$($sg.startClose)&rarr;`$$($sg.endClose) ($sign$($sg.chgPct)%)<br>구간 범위 `$$($sg.segLow)~`$$($sg.segHigh)</div></div>`n")
  }

  # ---- MA rows ----
  function MaRow($label, $val) {
    $badge = if ($price -gt $val) { "<span class=`"badge b-green`">가격 상회</span>" } else { "<span class=`"badge b-red`">가격 하회</span>" }
    return "<div class=`"ir`"><span class=`"il`">$label (`$$val)</span>$badge</div>"
  }
  $maRows = (MaRow '5일선' $ch.ma5) + (MaRow '20일선' $ch.ma20) + (MaRow '60일선' $ch.ma60) + (MaRow '120일선' $ch.ma120)

  # ---- annual chart data (JS arrays), pad missing to avoid JS errors ----
  $revJs = "[" + (($revA | ForEach-Object { [math]::Round([double]$_.val/1e9,2) }) -join ',') + "]"
  $oiJs = "[" + (($oiA | ForEach-Object { [math]::Round([double]$_.val/1e9,2) }) -join ',') + "]"
  $niJs = "[" + (($niA | ForEach-Object { [math]::Round([double]$_.val/1e9,2) }) -join ',') + "]"
  $catsJs = "[" + (($niA | ForEach-Object { "'" + ([datetime]$_.end).ToString('yyyy') + "'" }) -join ',') + "]"

  $qLabelsJs = "['매출액','$oiLabel','순이익']"
  $qValsJs = "[" + ((@($m.revQLatest, $m.oiQLatest, $m.niQLatest) | ForEach-Object { if ($_) { [math]::Round([double]$_/1e9,2) } else { 0 } }) -join ',') + "]"

  # ---- annual/quarterly income rows ----
  $annualRowsLeft = ""
  if ($revA.Count -gt 0) { $annualRowsLeft += "<div class=`"ir`"><span class=`"il`">매출액</span><span class=`"iv`">$(Fmt-USD0 $revA[-1].val) ($(ArrowPctSpan $revGrowthYoY)) <span class=`"ev $($revEv.cls)`">$($revEv.label)</span></span></div>`n" }
  if ($oiA.Count -gt 0) { $annualRowsLeft += "<div class=`"ir`"><span class=`"il`">$oiLabel</span><span class=`"iv`">$(Fmt-USD0 $oiA[-1].val) ($(ArrowPctSpan $oiGrowthYoY)) <span class=`"ev $((Ev-Growth $oiGrowthYoY).cls)`">$((Ev-Growth $oiGrowthYoY).label)</span></span></div>`n" }
  if ($niA.Count -gt 0) { $annualRowsLeft += "<div class=`"ir`"><span class=`"il`">순이익</span><span class=`"iv`">$(Fmt-USD0 $niA[-1].val) ($(ArrowPctSpan $niGrowthYoY)) <span class=`"ev $($niEv.cls)`">$($niEv.label)</span></span></div>`n" }
  if ($epsA.Count -gt 0) { $annualRowsLeft += "<div class=`"ir`"><span class=`"il`">희석주당순이익</span><span class=`"iv`">`$$($epsA[-1].val) ($(ArrowPctSpan $epsGrowthYoY)) <span class=`"ev $($epsEv.cls)`">$($epsEv.label)</span></span></div>`n" }

  $annualRowsRight = ""
  if ($m.assetsFY) { $annualRowsRight += "<div class=`"ir`"><span class=`"il`">총자산</span><span class=`"iv`">$(Fmt-USD0 $m.assetsFY)</span></div>`n" }
  if ($m.liabFY) { $annualRowsRight += "<div class=`"ir`"><span class=`"il`">총부채</span><span class=`"iv`">$(Fmt-USD0 $m.liabFY)</span></div>`n" }
  if ($m.equityFY) { $annualRowsRight += "<div class=`"ir`"><span class=`"il`">총자본</span><span class=`"iv`">$(Fmt-USD0 $m.equityFY)</span></div>`n" }
  if ($m.divAnnualLatest) {
    $payoutSuffix = if ($payoutRatio) { " (배당성향 $payoutRatio%)" } else { "" }
    $annualRowsRight += "<div class=`"ir`"><span class=`"il`">주당배당금</span><span class=`"iv`">DPS `$$($m.divAnnualLatest)$payoutSuffix</span></div>`n"
  } else { $annualRowsRight += "<div class=`"ir`"><span class=`"il`">주당배당금</span><span class=`"iv`">배당 없음</span></div>`n" }

  $qRowsLeft = ""
  if ($m.revQLatest) { $qRowsLeft += "<div class=`"ir`"><span class=`"il`">분기 매출액</span><span class=`"iv`">$(Fmt-USD0 $m.revQLatest) ($(ArrowPctSpan $revQYoY) YoY)</span></div>`n" }
  if ($m.oiQLatest) { $qRowsLeft += "<div class=`"ir`"><span class=`"il`">분기 $oiLabel</span><span class=`"iv`">$(Fmt-USD0 $m.oiQLatest) ($(ArrowPctSpan $oiQYoY) YoY)</span></div>`n" }
  if ($m.niQLatest) { $qRowsLeft += "<div class=`"ir`"><span class=`"il`">분기순이익</span><span class=`"iv`">$(Fmt-USD0 $m.niQLatest) ($(ArrowPctSpan $niQYoY) YoY) <span class=`"ev $($niQEv.cls)`">$($niQEv.label)</span></span></div>`n" }
  if ($m.epsQLatest) { $qRowsLeft += "<div class=`"ir`"><span class=`"il`">분기 EPS (희석)</span><span class=`"iv`">`$$($m.epsQLatest) ($(ArrowPctSpan $epsQYoY) YoY) <span class=`"ev $($epsQEv.cls)`">$($epsQEv.label)</span></span></div>`n" }

  $qRowsRight = ""
  if ($m.assetsLatest) { $qRowsRight += "<div class=`"ir`"><span class=`"il`">총자산</span><span class=`"iv`">$(Fmt-USD0 $m.assetsLatest)</span></div>`n" }
  if ($m.equityLatest) { $qRowsRight += "<div class=`"ir`"><span class=`"il`">총자본</span><span class=`"iv`">$(Fmt-USD0 $m.equityLatest)</span></div>`n" }
  if ($m.divQLatest) { $qRowsRight += "<div class=`"ir`"><span class=`"il`">분기 배당금</span><span class=`"iv`">DPS `$$($m.divQLatest)</span></div>`n" }

  # ---- valuation rows ----
  $valRows = ""
  if ($per) { $valRows += "<div class=`"ind-row`"><div class=`"ind-nm`">PER (최근 회계연도 EPS)</div><div class=`"ind-note`">`$$price&divide;`$$latestEPS</div><div class=`"ind-val`">$($per)x</div><span class=`"ev $($perEv.cls)`" style=`"min-width:58px;text-align:center;`">$($perEv.label)</span></div>`n" }
  if ($fwdPer) { $valRows += "<div class=`"ind-row`"><div class=`"ind-nm`">Forward PER</div><div class=`"ind-note`">최근분기 EPS&times;4 연환산</div><div class=`"ind-val`">$($fwdPer)x</div><span class=`"ev $((Ev-PER $fwdPer).cls)`" style=`"min-width:58px;text-align:center;`">$((Ev-PER $fwdPer).label)</span></div>`n" }
  if ($pbr) { $valRows += "<div class=`"ind-row`"><div class=`"ind-nm`">PBR</div><div class=`"ind-note`">`$$price&divide;`$$bps (BPS)</div><div class=`"ind-val`">$($pbr)x</div><span class=`"ev $($pbrEv.cls)`" style=`"min-width:58px;text-align:center;`">$($pbrEv.label)</span></div>`n" }
  $divYieldDisp = if ($divYield) { "$divYield%" } else { "배당없음" }
  $valRows += "<div class=`"ind-row`"><div class=`"ind-nm`">배당수익률</div><div class=`"ind-note`">분기배당&times;4 연환산 기준</div><div class=`"ind-val`">$divYieldDisp</div><span class=`"ev $($yieldEv.cls)`" style=`"min-width:58px;text-align:center;`">$($yieldEv.label)</span></div>`n"

  # ---- key metrics g4 ----
  $g4 = "<div class=`"g4`">`n"
  $g4 += "<div class=`"met`"><div class=`"ml`">최근 종가 ($($ch.priceDate.Substring(5)))</div><div class=`"mv`">`$$price</div><div class=`"ms $(if($ch.dailyChgPct -ge 0){'up'}else{'dn'})`">$(PctStr $ch.dailyChgPct) &middot; $trendBadge</div></div>`n"
  if ($niA.Count -gt 0) { $g4 += "<div class=`"met`"><div class=`"ml`">${fyLabel}年 $oiLabel</div><div class=`"mv up`">$(if($oiA.Count -gt 0){Fmt-USD0 $oiA[-1].val}else{'N/A'})</div><div class=`"ms`">$(PctStr $oiGrowthYoY)</div></div>`n" }
  if ($niA.Count -gt 0) { $g4 += "<div class=`"met`"><div class=`"ml`">${fyLabel}年 순이익</div><div class=`"mv up`">$(Fmt-USD0 $niA[-1].val)</div><div class=`"ms`">$(PctStr $niGrowthYoY)</div></div>`n" }
  if ($m.epsQLatest) { $g4 += "<div class=`"met`"><div class=`"ml`">최근 분기 EPS</div><div class=`"mv up`">`$$($m.epsQLatest)</div><div class=`"ms`">$(PctStr $epsQYoY) YoY</div></div>`n" }
  $g4 += "</div>"

  $bullHtml = ($bulls | ForEach-Object { "<div class=`"ir`"><span class=`"il`">$($_.t)</span><span class=`"badge b-green`">$($_.b)</span></div>" }) -join "`n"
  $bearHtml = ($bears | ForEach-Object { "<div class=`"ir`"><span class=`"il`">$($_.t)</span><span class=`"badge b-red`">$($_.b)</span></div>" }) -join "`n"

  $sigBadges = New-Object System.Collections.Generic.List[string]
  if ($hcPct -ne $null) { $sigBadges.Add("<span class=`"badge $(if($hcPct -ge -5){'b-green'}else{'b-amber'})`">52주 고점 대비 $(PctStr $hcPct)</span>") }
  if ($lcPct -ne $null) { $sigBadges.Add("<span class=`"badge b-blue`">52주 저점 대비 $(PctStr $lcPct)</span>") }
  if ($price -gt $ch.ma20 -and $price -gt $ch.ma60 -and $price -gt $ch.ma120) { $sigBadges.Add("<span class=`"badge b-green`">중기 이동평균선 상회</span>") }
  elseif ($price -lt $ch.ma60 -and $price -lt $ch.ma120) { $sigBadges.Add("<span class=`"badge b-red`">중기 이동평균선 하회</span>") }

  # ---- timeline ----
  $tlItems = @()
  $tlItems += [PSCustomObject]@{ date=$ch.lo52Date; title="주가 `$$($ch.lo52) — 52주 최저"; dot='dot-neg'; tag='52주 최저'; tagCls='tag-neg' }
  $tlItems += [PSCustomObject]@{ date=$ch.hi52Date; title="주가 `$$($ch.hi52) — 52주 최고"; dot='dot-pos'; tag='52주 최고'; tagCls='tag-pos' }
  if ($niA.Count -gt 0) {
    $fyDate = ([datetime]$niA[-1].end).ToString('yyyy.MM.dd')
    $tlItems += [PSCustomObject]@{ date=$fyDate; title="${fyLabel}年 연간 실적 회계연도 종료 — 순이익 $(PctStr $niGrowthYoY)"; dot='dot-neu'; tag='연간 실적'; tagCls='tag-neu' }
  }
  if ($m.revQEnd) {
    $qDate = ([datetime]$m.revQEnd).ToString('yyyy.MM.dd')
    $tlItems += [PSCustomObject]@{ date=$qDate; title="최근 분기 실적 — 순이익 $(PctStr $niQYoY) YoY"; dot='dot-big'; tag='분기 실적'; tagCls='tag-big' }
  }
  $tlItems = $tlItems | Sort-Object { [datetime]::Parse($_.date.Replace('/','-')) }
  $tlHtml = ($tlItems | ForEach-Object {
    "<div class=`"tl-item`"><div class=`"tl-dot $($_.dot)`"></div><div class=`"tl-date`">$($_.date)</div><div class=`"tl-title`">$($_.title)</div><span class=`"tag $($_.tagCls)`">$($_.tag)</span></div>"
  }) -join "`n"

  $candleJs = Build-CandleJs $chartPath
  if (-not $candleJs) { $skippedList += "$t (no candle data)"; continue }

  $companyName = $s.name
  $industry = $s.ind
  $rank = $s.rank
  $rankStr = '{0:D3}' -f [int]$rank

  $html = @"
<link rel="stylesheet" href="../css/global.css">
<script src="../js/chart-common.js"></script>

<div style="padding:1rem 0;" class="box">

<div class="hl" style="margin-bottom:14px;">
  <div style="font-size:12px;font-weight:700;color:var(--color-text-success);">&#9989; 실 데이터 — SEC EDGAR 10-K/10-Q + Yahoo Finance 시세 기준 ($($ch.priceDate) 종가)</div>
</div>

<div style="margin-bottom:4px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;">
  <h2>$companyName ($t)</h2>
  <span class="badge b-se">US &middot; $industry</span>
  <span class="badge b-gray">$trendBadge</span>
  <span class="src">&#128196; <a href="https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=$t&type=10-K&dateb=&owner=include&count=40" target="_blank" rel="noopener">SEC EDGAR 10-K/10-Q 원문</a> + &#128202; <a href="https://finance.yahoo.com/quote/$t" target="_blank" rel="noopener">Yahoo Finance 시세</a></span>
</div>
<p class="sub">최근 종가 `$$price ($($ch.priceDate), 전일대비 $(PctStr $ch.dailyChgPct)) &middot; 52주 최고 `$$($ch.hi52) ($($ch.hi52Date)) &middot; 52주 최저 `$$($ch.lo52) ($($ch.lo52Date))$(if($mktCap){" &middot; 시총 약 $(Fmt-USD $mktCap)"})</p>

<div style="background:var(--color-background-info);border-left:3px solid var(--color-navy);border-radius:var(--border-radius-md);padding:10px 14px;margin-bottom:14px;">
  <div style="font-size:12px;color:var(--color-navy);line-height:1.6;"><strong>&#128273; 투자 요약:</strong> $keyInsightText</div>
</div>

$g4

<div class="card">
  <div class="sec">1. 기술적 분석 — 일봉 기준 (최근 1년)</div>
  <div id="c$($t)ChartControls" class="kc-controls"></div>
  <svg id="c$($t)Svg" viewBox="0 0 720 240" width="100%" style="display:block;margin-bottom:12px;background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:4px;"></svg>

  <div style="font-size:13px;font-weight:600;margin-bottom:8px;">&#128202; 구간별 분석 <span class="src">&#128202; Yahoo Finance 일봉</span></div>
  <div class="g4" style="font-size:11px;margin-bottom:12px;">
$($segHtml.ToString())
  </div>

  <div class="g2" style="margin-bottom:12px;">
    <div>
      <div style="font-size:13px;font-weight:600;margin-bottom:7px;">이동평균선 현황</div>
      $maRows
    </div>
    <div>
      <div style="font-size:13px;font-weight:600;margin-bottom:7px;">핵심 가격대</div>
      <div class="ir"><span class="il">52주 최고</span><span style="font-weight:600;color:var(--color-navy);">`$$($ch.hi52) ($($ch.hi52Date))</span></div>
      <div class="ir"><span class="il">최근 종가</span><span style="font-weight:600;color:var(--color-text-primary);">`$$price</span></div>
      <div class="ir"><span class="il">52주 최저</span><span style="font-weight:600;">`$$($ch.lo52) ($($ch.lo52Date))</span></div>
      <div class="ir"><span class="il">LC(저점比) / HC(고점比)</span><span style="font-weight:600;">$(PctStr $lcPct) / $(PctStr $hcPct)</span></div>
    </div>
  </div>

  <div class="sig">
    $($sigBadges -join "`n    ")
  </div>
</div>

<div class="card">
  <div class="sec">2. 기본적 분석 — 공시 원문 <span class="src">&#128196; 10-K($fyLabel) + 10-Q(최근 분기)</span></div>

  <div style="display:flex;gap:8px;margin-bottom:14px;">
    <button id="btnAnnual" onclick="switchTab('annual')" style="flex:1;display:flex;align-items:center;justify-content:center;gap:7px;padding:10px 0;border-radius:3px;border:1.5px solid var(--color-navy);background:var(--color-navy);color:#fff;font-size:13px;font-weight:600;cursor:pointer;">
      &#128196; 연간(10-K) <span style="font-size:11px;opacity:.85;font-weight:400;">$fyLabel</span>
    </button>
    <button id="btnQuarter" onclick="switchTab('quarter')" style="flex:1;display:flex;align-items:center;justify-content:center;gap:7px;padding:10px 0;border-radius:3px;border:1.5px solid var(--color-border-tertiary);background:var(--color-background-secondary);color:var(--color-text-secondary);font-size:13px;font-weight:500;cursor:pointer;">
      &#128203; 분기(10-Q) <span style="font-size:11px;opacity:.85;font-weight:400;">최근 분기</span>
    </button>
  </div>

  <div id="tabAnnual">
    <svg id="c$($t)AnnualChart" viewBox="0 0 680 190" width="100%" style="display:block;margin-bottom:12px;"></svg>
    <div style="font-size:12px;font-weight:600;color:var(--color-text-secondary);margin-bottom:6px;">&#128202; 손익 요약 (단위: `$B &middot; ${fyLabel}年)</div>
    <div class="g2" style="margin-bottom:12px;">
      <div>$annualRowsLeft</div>
      <div>$annualRowsRight</div>
    </div>
  </div>

  <div id="tabQuarter" style="display:none;">
    <svg id="c$($t)QtrChart" viewBox="0 0 680 190" width="100%" style="display:block;margin-bottom:12px;"></svg>
    <div style="font-size:12px;font-weight:600;color:var(--color-text-secondary);margin-bottom:6px;">&#128202; 최근 분기 손익 요약 (단위: `$B)</div>
    <div class="g2" style="margin-bottom:12px;">
      <div>$qRowsLeft</div>
      <div>$qRowsRight</div>
    </div>
  </div>
</div>

<div class="card">
  <div class="sec">3. 상대 투자지표 — 최근 종가 `$$price 기준</div>
  $valRows
</div>

<div class="card">
  <div class="sec">4. 시계열 주요 이벤트 <span class="src">&#128196; SEC EDGAR + &#128202; Yahoo Finance</span></div>
  <div class="tl">
$tlHtml
  </div>
</div>

<div class="card">
  <div class="sec">5. 핵심 투자 포인트</div>
  <div class="g2">
    <div>
      <div style="font-size:13px;font-weight:600;margin-bottom:7px;color:var(--color-text-success);">긍정 요인 (Bull)</div>
      $bullHtml
    </div>
    <div>
      <div style="font-size:13px;font-weight:600;margin-bottom:7px;color:var(--color-text-danger);">리스크 (Bear)</div>
      $bearHtml
    </div>
  </div>
  <div style="margin-top:10px;font-size:11px;color:var(--color-text-tertiary);text-align:center;">&#9888; 10-K/10-Q SEC EDGAR 원문 + Yahoo Finance 일봉($($ch.priceDate) 종가) 기준 &middot; 서술은 실 수치 기반 규칙으로 자동 생성 &middot; 투자 권고가 아닙니다</div>
</div>

</div>

<script>
function switchTab(tab) {
  const isA=tab==='annual';
  document.getElementById('tabAnnual').style.display=isA?'':'none';
  document.getElementById('tabQuarter').style.display=isA?'none':'';
  const aS='flex:1;display:flex;align-items:center;justify-content:center;gap:7px;padding:10px 0;border-radius:3px;font-size:13px;cursor:pointer;background:#0B2545;border:1.5px solid #0B2545;color:#fff;font-weight:600;';
  const iS='flex:1;display:flex;align-items:center;justify-content:center;gap:7px;padding:10px 0;border-radius:3px;font-size:13px;cursor:pointer;background:var(--color-background-secondary);border:1.5px solid var(--color-border-tertiary);color:var(--color-text-secondary);font-weight:500;';
  document.getElementById('btnAnnual').style.cssText=isA?aS:iS;
  document.getElementById('btnQuarter').style.cssText=isA?iS:aS;
  if(!isA && !window._qDrawn){ window._qDrawn=true; drawQtrChart(); }
}
function cssVar(name){ return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
function svgEl(tag,attrs){ const e=document.createElementNS('http://www.w3.org/2000/svg',tag); for(const k in attrs) e.setAttribute(k,attrs[k]); return e; }

function drawAnnualChart(){
  const svg=document.getElementById('c$($t)AnnualChart');
  const W=680,H=190,pL=44,pR=44,pT=16,pB=26;
  const cW=W-pL-pR,cH=H-pT-pB;
  const cats=$catsJs;
  const rev=$revJs;
  const oi=$oiJs;
  const ni=$niJs;
  if(cats.length===0 || rev.length===0){ return; }
  const maxV=Math.max(...rev,...oi,...ni)*1.15;
  const groupW=cW/cats.length;
  const barW=groupW*0.26;
  function py(v){ return pT+cH*(1-v/maxV); }
  [0,0.25,0.5,0.75,1].forEach(f=>{ const y=py(maxV*f); svg.appendChild(svgEl('line',{x1:pL,x2:W-pR,y1:y,y2:y,stroke:cssVar('--color-border-tertiary'),'stroke-width':1})); });
  const revCol='#8C97A5', oiCol='#0B2545', niCol='#A6811A';
  const pts=[];
  cats.forEach((cat,i)=>{
    const gx=pL+i*groupW+groupW/2;
    const rx=gx-barW-2, ox=gx+2;
    if (rev[i] !== undefined) {
      const rTop=py(rev[i]);
      svg.appendChild(svgEl('rect',{x:rx,y:rTop,width:barW,height:py(0)-rTop,fill:revCol,rx:2,opacity:0.55}));
      const t1=svgEl('text',{x:rx+barW/2,y:rTop-4,'text-anchor':'middle','font-size':9,fill:revCol}); t1.textContent='`$'+rev[i].toFixed(0)+'B'; svg.appendChild(t1);
    }
    if (oi[i] !== undefined) {
      const oTop=py(oi[i]);
      svg.appendChild(svgEl('rect',{x:ox,y:oTop,width:barW,height:py(0)-oTop,fill:oiCol,rx:2}));
      const t2=svgEl('text',{x:ox+barW/2,y:oTop-4,'text-anchor':'middle','font-size':9,fill:oiCol,'font-weight':600}); t2.textContent='`$'+oi[i].toFixed(0)+'B'; svg.appendChild(t2);
    }
    const t3=svgEl('text',{x:gx,y:H-6,'text-anchor':'middle','font-size':10,fill:cssVar('--color-text-secondary')}); t3.textContent=cat; svg.appendChild(t3);
    if (ni[i] !== undefined) pts.push([gx, py(ni[i])]);
  });
  if(pts.length>1){ svg.appendChild(svgEl('polyline',{points:pts.map(p=>p.join(',')).join(' '),fill:'none',stroke:niCol,'stroke-width':2.5})); }
  pts.forEach((p,i)=>{ svg.appendChild(svgEl('circle',{cx:p[0],cy:p[1],r:4,fill:niCol})); const t=svgEl('text',{x:p[0],y:p[1]-9,'text-anchor':'middle','font-size':9,fill:niCol,'font-weight':600}); t.textContent='`$'+ni[i].toFixed(0)+'B'; svg.appendChild(t); });
  const legend=[[revCol,'매출액'],[oiCol,'$oiLabel'],[niCol,'순이익']];
  legend.forEach((l,i)=>{ const lx=pL+i*90; svg.appendChild(svgEl('rect',{x:lx,y:2,width:9,height:9,fill:l[0],rx:2})); const t=svgEl('text',{x:lx+12,y:10,'font-size':9,fill:cssVar('--color-text-secondary')}); t.textContent=l[1]; svg.appendChild(t); });
}

function drawQtrChart(){
  const svg=document.getElementById('c$($t)QtrChart');
  const W=680,H=190,pL=44,pR=20,pT=20,pB=30;
  const cW=W-pL-pR,cH=H-pT-pB;
  const labels=$qLabelsJs;
  const vals=$qValsJs;
  const cols=['#8C97A5','#0B2545','#A6811A'];
  const maxV=Math.max(...vals,1)*1.15;
  const groupW=cW/labels.length;
  const barW=groupW*0.5;
  function py(v){ return pT+cH*(1-v/maxV); }
  [0,25,50,75,100].forEach(v=>{ const val=v/100*maxV; const y=py(val); svg.appendChild(svgEl('line',{x1:pL,x2:W-pR,y1:y,y2:y,stroke:cssVar('--color-border-tertiary'),'stroke-width':1})); });
  labels.forEach((lab,i)=>{
    const gx=pL+i*groupW+groupW/2;
    const top=py(vals[i]);
    svg.appendChild(svgEl('rect',{x:gx-barW/2,y:top,width:barW,height:py(0)-top,fill:cols[i],rx:3}));
    const t1=svgEl('text',{x:gx,y:top-6,'text-anchor':'middle','font-size':10,fill:cssVar('--color-text-primary'),'font-weight':600}); t1.textContent='`$'+vals[i].toFixed(1)+'B'; svg.appendChild(t1);
    const t2=svgEl('text',{x:gx,y:H-8,'text-anchor':'middle','font-size':9,fill:cssVar('--color-text-secondary')}); t2.textContent=lab; svg.appendChild(t2);
  });
}
drawAnnualChart();

const data = $candleJs;
renderCandleChart({svgId:'c$($t)Svg', controlsId:'c$($t)ChartControls', data: data});
</script>
"@

  $outPath = Join-Path $root "stocks\$rankStr`_$t.html"
  [System.IO.File]::WriteAllText($outPath, $html, $utf8NoBom)
  $generated++
}

Write-Host "Generated $generated pages."
if ($skippedList.Count -gt 0) {
  Write-Host "Skipped ($($skippedList.Count)):"
  $skippedList | ForEach-Object { Write-Host "  $_" }
}
