<#
.SYNOPSIS
    Safely deploys static or ASP.NET content from Jenkins artifacts to IIS.

.DESCRIPTION
    1. Checks IIS service (W3SVC)
    2. Writes app_offline.htm (graceful maintenance mode)
    3. Stops (or creates) the target App Pool
    4. Mirrors files from Jenkins build output using Robocopy
    5. Restarts the App Pool with retry logic
    6. Removes maintenance file
    7. Logs operations to %TEMP%\robocopy-deploy.log
#>

param(
  [string]$AppPool  = 'Site1Pool',
  [string]$SitePath = 'C:\inetpub\labiba\Site1',        # actual IIS site root
  [string]$BuildDir = "$env:WORKSPACE\artifact"          # built by Jenkins pipeline
)

Import-Module WebAdministration -ErrorAction Stop

Write-Host "============================================================="
Write-Host "🚀 Starting Deployment to IIS"
Write-Host "-------------------------------------------------------------"
Write-Host "App Pool : $AppPool"
Write-Host "Site Path: $SitePath"
Write-Host "Build Dir: $BuildDir"
Write-Host "============================================================="

# --- Check IIS Service Status ---
$service = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
if (-not $service) {
    throw "❌ IIS service (W3SVC) not found. Is IIS installed?"
}
if ($service.Status -ne 'Running') {
    Write-Host "==> Starting IIS service (W3SVC)..."
    Start-Service 'W3SVC'
    Start-Sleep -Seconds 3
}
Write-Host "✅ IIS service is running."

# --- Maintenance Mode (app_offline.htm) ---
$appOffline = Join-Path $SitePath 'app_offline.htm'
try {
    'Maintenance in progress…' | Out-File -Encoding utf8 -FilePath $appOffline -Force
    Write-Host "==> app_offline.htm placed for maintenance mode."
} catch {
    Write-Warning "⚠️ Could not create app_offline.htm: $_"
}

# --- Stop or Create App Pool ---
if (Test-Path "IIS:\AppPools\$AppPool") {
    Write-Host "==> Stopping App Pool $AppPool..."
    try {
        Stop-WebAppPool -Name $AppPool -ErrorAction Stop
        Start-Sleep -Seconds 3
        Write-Host "✅ App Pool stopped successfully."
    } catch {
        Write-Warning "⚠️ Failed to stop App Pool (might already be stopped): $_"
    }
} else {
    Write-Host "==> Creating new App Pool $AppPool"
    New-WebAppPool -Name $AppPool | Out-Null
}

# --- Validate Build Output ---
if (-not (Test-Path $BuildDir)) {
    throw "❌ Build output not found: $BuildDir"
}
Write-Host "✅ Build directory validated."

# --- Ensure Destination Exists ---
if (-not (Test-Path $SitePath)) {
    Write-Host "==> Creating site directory $SitePath"
    New-Item -ItemType Directory -Path $SitePath -Force | Out-Null
}

# --- Sync Files Using Robocopy ---
Write-Host "==> Syncing content from build to site..."
$rcLog = Join-Path $env:TEMP "robocopy-deploy.log"
$excludeDirs = @("workspace", "@tmp", "durable*", "logs")

# Build robocopy arguments
$robocopyArgs = @()
$robocopyArgs += "`"$BuildDir`""
$robocopyArgs += "`"$SitePath`""
$robocopyArgs += "*.* /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:`"$rcLog`""
foreach ($dir in $excludeDirs) { $robocopyArgs += "/XD `"$dir`"" }

cmd.exe /c "robocopy $($robocopyArgs -join ' ')"
$exitCode = $LASTEXITCODE

if ($exitCode -ge 8) {
    throw "❌ Robocopy failed (exit code $exitCode). Check log: $rcLog"
}
Write-Host "✅ Files synchronized successfully."
Write-Host "📄 Log File: $rcLog"

# --- Restart App Pool with Retry Logic ---
Write-Host "==> Starting App Pool $AppPool (with retry)..."
$maxRetries = 5
$retry = 0
$started = $false

while (-not $started -and $retry -lt $maxRetries) {
    try {
        Start-Sleep -Seconds 3
        Start-WebAppPool -Name $AppPool -ErrorAction Stop
        $state = (Get-WebAppPoolState -Name $AppPool).Value
        if ($state -eq 'Started') {
            Write-Host "✅ App Pool $AppPool started successfully."
            $started = $true
            break
        } else {
            throw "Current state: $state"
        }
    }
    catch {
        $retry++
        Write-Warning ("Attempt ${retry}: App Pool not ready yet. Waiting...")
        if ($retry -eq $maxRetries) {
            Write-Error "❌ Failed to start App Pool after $maxRetries attempts."
            throw
        }
    }
}

# --- Remove Maintenance File ---
Remove-Item $appOffline -ErrorAction SilentlyContinue
Write-Host "✅ app_offline.htm removed."

Write-Host "==> Deployment completed successfully!"
Write-Host "============================================================="
exit 0
