# Minimal local HTTP server for the salon expenses app.
# Serves only files inside this script's own folder.
# No admin rights required (plain TcpListener, not HttpListener).
# After start it opens the app in Edge/Chrome app mode, then serves
# until 2 hours of inactivity.
# Use -Lan switch to also accept phones on the salon Wi-Fi.
param([switch]$Lan)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$marker = "salon-expenses-server-ok"

function Test-PortOpen {
  param([int]$Port)
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(400)) { $tcp.Close(); return $false }
    $tcp.EndConnect($ar) | Out-Null
    $tcp.Close()
    return $true
  } catch { return $false }
}

function Test-OurServer {
  param([int]$Port)
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $stream.WriteTimeout = 2000
    $stream.ReadTimeout = 2000
    $req = [System.Text.Encoding]::ASCII.GetBytes("GET /__ping HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
    $stream.Write($req, 0, $req.Length)
    $stream.Flush()
    $buf = New-Object byte[] 4096
    $n = $stream.Read($buf, 0, $buf.Length)
    $tcp.Close()
    if ($n -gt 0) {
      $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
      return ($text -like "*$marker*")
    }
    return $false
  } catch { return $false }
}

function Find-Browser {
  $cands = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
  )
  foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}

function Open-App {
  param([string]$Url)
  $exe = Find-Browser
  if ($exe) {
    Start-Process -FilePath $exe -ArgumentList "--app=$Url" | Out-Null
  } else {
    Start-Process -FilePath $Url | Out-Null
  }
}

function Get-Mime {
  param([string]$Path)
  switch ([System.IO.Path]::GetExtension($Path).ToLower()) {
    ".html" { return "text/html; charset=utf-8" }
    ".js"   { return "application/javascript; charset=utf-8" }
    ".css"  { return "text/css; charset=utf-8" }
    ".json" { return "application/json; charset=utf-8" }
    ".png"  { return "image/png" }
    ".jpg"  { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".gif"  { return "image/gif" }
    ".svg"  { return "image/svg+xml" }
    ".ico"  { return "image/x-icon" }
    ".txt"  { return "text/plain; charset=utf-8" }
    ".wasm" { return "application/wasm" }
    default { return "application/octet-stream" }
  }
}

function Send-Response {
  param($Stream, [string]$Status, [string]$Type, [byte[]]$Bytes, [string]$Method)
  $reasons = @{ "200" = "OK"; "400" = "Bad Request"; "403" = "Forbidden"; "404" = "Not Found"; "405" = "Method Not Allowed" }
  $reason = $reasons[$Status]
  if (-not $reason) { $reason = "Error" }
  $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $Type`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`nCache-Control: no-cache`r`n`r`n"
  $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($hb, 0, $hb.Length)
  if ($Method -ne "HEAD" -and $Bytes.Length -gt 0) {
    $Stream.Write($Bytes, 0, $Bytes.Length)
  }
  $Stream.Flush()
}

# ---- pick a port: reuse our running instance, else first free port ----
$port = 0
foreach ($p in 8177..8186) {
  if (Test-OurServer -Port $p) { Open-App -Url "http://127.0.0.1:$p/"; exit }
  if (-not (Test-PortOpen -Port $p)) { $port = $p; break }
}
if ($port -eq 0) {
  $sh = New-Object -ComObject WScript.Shell
  $sh.Popup("Не удалось занять локальный порт для приложения (8177-8186 заняты). Закройте другие копии приложения и попробуйте снова.", 0, "Расходы Кератин Бара", 48) | Out-Null
  exit 1
}

$bindAddr = [System.Net.IPAddress]::Loopback
if ($Lan) { $bindAddr = [System.Net.IPAddress]::Any }
$listener = New-Object System.Net.Sockets.TcpListener($bindAddr, $port)
$listener.Start()
Open-App -Url "http://127.0.0.1:$port/"

if ($Lan) {
  $lanIp = $null
  try {
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
      Select-Object -First 1).IPAddress
  } catch { }
  $sh = New-Object -ComObject WScript.Shell
  if ($lanIp) {
    $sh.Popup("Телефон (в той же Wi-Fi сети) открывает адрес:`r`n`r`nhttp://${lanIp}:$port/`r`n`r`nВне салона этот адрес работать не будет. Если Windows спросит про брандмауэр — нажмите «Разрешить доступ» (частные сети).", 0, "Расходы Кератин Бара — доступ для телефона", 64) | Out-Null
  } else {
    $sh.Popup("Не удалось определить адрес компьютера в сети. Телефон не сможет подключиться.", 0, "Расходы Кератин Бара", 48) | Out-Null
  }
}

$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
$last = Get-Date

while (((Get-Date) - $last).TotalMinutes -lt 120) {
  if (-not $listener.Pending()) { Start-Sleep -Milliseconds 150; continue }
  $last = Get-Date
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 10000
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)
    $requestLine = $reader.ReadLine()
    if ($null -eq $requestLine -or $requestLine -eq "") { $reader.Dispose(); $client.Close(); continue }
    while ($true) {
      $h = $reader.ReadLine()
      if ($null -eq $h -or $h -eq "") { break }
    }
    $reader.Dispose()

    $parts = $requestLine -split " "
    if ($parts.Length -lt 2) {
      Send-Response -Stream $stream -Status "400" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes("bad request")) -Method "GET"
      $client.Close(); continue
    }
    $method = $parts[0].ToUpper()
    $url = $parts[1]
    if ($url.Contains("?")) { $url = $url.Substring(0, $url.IndexOf("?")) }
    $url = [System.Uri]::UnescapeDataString($url)

    if ($url -eq "/__ping") {
      Send-Response -Stream $stream -Status "200" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes($marker)) -Method $method
      $client.Close(); continue
    }
    if ($method -ne "GET" -and $method -ne "HEAD") {
      Send-Response -Stream $stream -Status "405" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes("method not allowed")) -Method $method
      $client.Close(); continue
    }

    if ($url -eq "/") { $url = "/index.html" }
    if ($url.Contains("..") -or $url -match "^[a-zA-Z]:") {
      Send-Response -Stream $stream -Status "403" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes("forbidden")) -Method $method
      $client.Close(); continue
    }

    $rel = $url.TrimStart("/") -replace "/", "\"
    $diskPath = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
    if (-not $diskPath.StartsWith($rootFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
      Send-Response -Stream $stream -Status "403" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes("forbidden")) -Method $method
      $client.Close(); continue
    }
    if ([System.IO.Directory]::Exists($diskPath)) {
      $diskPath = Join-Path $diskPath "index.html"
    }
    if (-not [System.IO.File]::Exists($diskPath)) {
      Send-Response -Stream $stream -Status "404" -Type "text/plain" -Bytes ([System.Text.Encoding]::ASCII.GetBytes("not found")) -Method $method
      $client.Close(); continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($diskPath)
    Send-Response -Stream $stream -Status "200" -Type (Get-Mime -Path $diskPath) -Bytes $bytes -Method $method
    $client.Close()
  } catch {
    try { $client.Close() } catch { }
  }
}
$listener.Stop()
