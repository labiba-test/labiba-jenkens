param(
  [string]$AppPool    = 'Site1Pool',
  [string]$SitePath   = 'C:\inetpub\labiba\Site1',
  [string]$BuildDir   = "$env:WORKSPACE\artifact"
)

Import-Module WebAdministration

Write-Host "==> Starting deployment..."

# Graceful drain (optional)
$appOffline = Join-Path $SitePath 'app_offline.htm'
'Maintenance in progress...' | Out-File -Encoding utf8 -FilePath $appOffline -Force

# Stop or create app pool
if (Test-Path "IIS:\AppPools\$AppPool") {
  Write-Host "==> Stopping app pool $AppPool"
  Stop-WebAppPool -Name $AppPool -ErrorAction SilentlyContinue
} else {
  Write-Host "!! App pool $AppPool not found. Creating new one."
  New-WebAppPool -Name $AppPool | Out-Null
}

# Validate build output
if (-not (Test-Path $BuildDir)) {
  throw "Build output not found: $BuildDir"
}

# Ensure destination exists
if (-not (Test-Path $SitePath)) { 
  New-Item -ItemType Directory -Path $SitePath -Force | Out-Null 
}

# Sync new content
Write-Host "==> Syncing content from $BuildDir to $SitePath"
$rcLog = Join-Path $env:TEMP "robocopy-deploy.log"
& robocopy $BuildDir $SitePath *.* /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:$rcLog /XD "workspace" "@tmp"

# Reapply permissions just in case
$appPoolIdentity = "IIS AppPool\$AppPool"
icacls $SitePath /grant "${appPoolIdentity}:(OI)(CI)(M)" /T | Out-Null
icacls $SitePath /grant "IIS_IUSRS:(OI)(CI)(RX,M)" /T | Out-Null

# Retry logic to start the app pool
$maxRetries = 5
$retryDelay = 3
for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Start-WebAppPool -Name $AppPool -ErrorAction Stop
        Write-Host "✅ App pool $AppPool started successfully (attempt $i)."
        break
    } catch {
        Write-Warning "⚠️ Attempt $i: IIS still busy, waiting $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        if ($i -eq $maxRetries) {
            throw "❌ App pool $AppPool failed to start after $maxRetries attempts."
        }
    }
}

# Remove maintenance page
Remove-Item $appOffline -ErrorAction SilentlyContinue

Write-Host "==> Deployment complete."
