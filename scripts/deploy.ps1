param(
  [string]$AppPool    = 'Site1Pool',
  [string]$SitePath   = 'C:\inetpub\labiba\Site1',
  [string]$BuildDir   = "$env:WORKSPACE\artifact"
)

Import-Module WebAdministration
Write-Host "==> Starting deployment..."

# Step 1: Gracefully drain live traffic
$appOffline = Join-Path $SitePath 'app_offline.htm'
'Maintenance in progress...' | Out-File -Encoding utf8 -FilePath $appOffline -Force

# Step 2: Stop or create app pool
if (Test-Path "IIS:\AppPools\$AppPool") {
    Write-Host "==> Stopping app pool $AppPool"
    Stop-WebAppPool -Name $AppPool -ErrorAction SilentlyContinue
} else {
    Write-Host "!! App pool $AppPool not found. Creating it."
    New-WebAppPool -Name $AppPool | Out-Null
}

# Step 3: Validate build output
if (-not (Test-Path $BuildDir)) {
    throw "Build output not found: $BuildDir"
}

# Step 4: Ensure target path exists
if (-not (Test-Path $SitePath)) {
    New-Item -ItemType Directory -Path $SitePath -Force | Out-Null
}

# Step 5: Sync content safely
Write-Host "==> Syncing content from $BuildDir to $SitePath"
$rcLog = Join-Path $env:TEMP "robocopy-deploy.log"
& robocopy $BuildDir $SitePath *.* /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:$rcLog /XD "workspace" "@tmp"

# Step 6: Reapply permissions
$appPoolIdentity = "IIS AppPool\$AppPool"
Write-Host "==> Reapplying IIS permissions..."
icacls $SitePath /grant "${appPoolIdentity}:(OI)(CI)(M)" /T | Out-Null
icacls $SitePath /grant "IIS_IUSRS:(OI)(CI)(RX,M)" /T | Out-Null

# Step 7: Retry logic to start app pool
$maxRetries = 5
$retryDelay = 3
for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Start-WebAppPool -Name $AppPool -ErrorAction Stop
        Write-Host "App pool $AppPool started successfully (attempt $i)."
        break
    } catch {
        Write-Warning ("Attempt {0}: IIS still busy, waiting {1} seconds..." -f $i, $retryDelay)
        Start-Sleep -Seconds $retryDelay
        if ($i -eq $maxRetries) {
            throw "App pool $AppPool failed to start after $maxRetries attempts."
        }
    }
}

# Step 8: Remove maintenance file
Remove-Item $appOffline -ErrorAction SilentlyContinue

Write-Host "==> Deployment complete."
