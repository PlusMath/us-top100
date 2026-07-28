param([string]$file, [string]$outfile)
$d = Get-Content $file -Raw | ConvertFrom-Json
$res = $d.chart.result[0]
$ts = $res.timestamp
$q = $res.indicators.quote[0]
$n = $ts.Count
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('[')
for ($i=0; $i -lt $n; $i++) {
  if ($null -eq $q.close[$i]) { continue }
  $dt = [DateTimeOffset]::FromUnixTimeSeconds($ts[$i]).UtcDateTime.ToString('yyyy-MM-dd')
  $o = [math]::Round($q.open[$i],2); $h=[math]::Round($q.high[$i],2); $l=[math]::Round($q.low[$i],2); $c=[math]::Round($q.close[$i],2)
  [void]$sb.Append("{d:'$dt',o:$o,h:$h,l:$l,c:$c},")
}
[void]$sb.Append(']')
$js = $sb.ToString() -replace ',\]',']'
[System.IO.File]::WriteAllText($outfile, $js, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outfile ($n points)"
