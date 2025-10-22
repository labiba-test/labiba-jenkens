<#
.SYNOPSIS
    Deploy static or ASP.NET content from Jenkins artifact to IIS.

.DESCRIPTION
    • Writes app_offline.htm (optional graceful drain)
    • Stops or creates the target App Pool
    • Syncs files using robocopy (/MIR)
    • Restarts App Pool with retry logic
    • Cleans up maintenance file
    • Logs to %TEMP%\robocopy-deploy.log
#>

param(
  [string]$AppPool  = 'Site1Pool',
  [string]$SitePath = 'C:\inetpub\labiba\Site1',         # actual IIS site root
  [string]$BuildDir = "$env:WORKSPACE\artifact"          # built by Jenkins pipeline
)

Import-Module WebAdministration -ErrorAction Stop

Write-Host "============================================================="
Write-Host "🚀 Deploying to IIS Site Path: $SitePath"
Write-Host "App Pool : $AppPool"
Write-Host "Build Dir: $BuildDir"
Write-Host "============================================================="

# --- Maintenance mode (app_offline)
$appOffline = Join-Path $SitePath 'app_offline.htm'
try {
    'Maintenance in progress…' | Out-File -Encoding utf8 -FilePath $appOffline -Force
} catch {
    Write-Warning "Could not create app_offline.htm: $_"
}

# --- Stop or create App Pool
if (Test-Path "IIS:\AppPools\$AppPool") {
    Write-Host "==> Stopping App Pool $AppPool"
    try {
        Stop-WebAppPool -Name $AppPool -ErrorAction Stop
        Start-Sleep -Seconds 3
    } catch {
        Write-Warning "App Pool stop warning: $_"
    }
} else {
    Write-Host "==> Creating new App Pool $AppPool"
    New-WebAppPool -Name $AppPool | Out-Null
}

# --- Validate build folder
if (-not (Test-Path $BuildDir)) {
    throw "Build output not found: $BuildDir"
}

# --- Ensure destination folder exists
if (-not (Test-Path $SitePath)) {
    Write-Host "==> Creating site path $SitePath"
    New-Item -ItemType Directory -Path $SitePath -Force | Out-Null
}

# --- Sync files using Robocopy
Write-Host "==> Syncing new content to $SitePath ..."
$rcLog = Join-Path $env:TEMP "robocopy-deploy.log"
$excludeDirs = @("workspace", "@tmp", "durable*", "logs")
$robocopyArgs = "$BuildDir $SitePath *.* /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:`"$rcLog`""

foreach ($dir in $excludeDirs) { $robocopyArgs += " /XD `"$dir`"" }

cmd.exe /c "robocopy $robocopyArgs"
$exitCode = $LASTEXITCODE

if ($exitCode -ge 8) {
    throw "Robocopy failed (exit code $exitCode). Check $rcLog"
}
Write-Host "✅ Content synchronized successfully."
Write-Host "Log File : $rcLog"

# --- Restart App Pool with retry logic
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
        }
    }
    catch {
        $retry++
        Write-Warning "Attempt $retry: App Pool not ready yet..."
        if ($retry -eq $maxRetries) {
            Write-Error "❌ Failed to start App Pool after $maxRetries attempts."
            throw
        }
    }
}

# --- Remove maintenance file
Remove-Item $appOffline -ErrorAction SilentlyContinue
Write-Host "==> Deployment complete."
Write-Host "============================================================="
