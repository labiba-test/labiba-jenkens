param(
  [string]$AppPool    = 'Site1Pool',
  [string]$SitePath   = 'C:\inetpub\labiba\Site1',                    # <— real IIS webroot, NOT the Jenkins workspace/share
  [string]$BuildDir   = "$env:WORKSPACE\artifact"                      # created by the build stage
)

Import-Module WebAdministration

Write-Host "==> Starting deployment..."

# Graceful drain (optional but nice for ASP.NET/ASP.NET Core)
# Write a temporary app_offline.htm to quiesce requests
$appOffline = Join-Path $SitePath 'app_offline.htm'
'Maintenance...' | Out-File -Encoding utf8 -FilePath $appOffline -Force
# For classic ASP.NET or if you prefer app pool control:
if (Test-Path "IIS:\AppPools\$AppPool") {
  Write-Host "==> Stopping app pool $AppPool"
  Stop-WebAppPool -Name $AppPool
} else {
  Write-Host "!! App pool $AppPool not found. Creating it."
  New-WebAppPool -Name $AppPool | Out-Null
}

# Validate build output
if (-not (Test-Path $BuildDir)) {
  throw "Build output not found: $BuildDir"
}

# Ensure destination exists
if (-not (Test-Path $SitePath)) { New-Item -ItemType Directory -Path $SitePath -Force | Out-Null }

Write-Host "==> Syncing content to $SitePath"
# Use robocopy for reliable sync, exclude Jenkins temp/workspace dirs just in case
$rcLog = Join-Path $env:TEMP "robocopy-deploy.log"
# /MIR mirrors (delete extras at dest); /XD excludes directories; /R:2 /W:2 keeps retries short
& robocopy $BuildDir $SitePath *.* /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:$rcLog /XD "workspace" "@tmp"

# Bring the app back
if (Test-Path "IIS:\AppPools\$AppPool") {
  Write-Host "==> Starting app pool $AppPool"
  Start-WebAppPool -Name $AppPool
}
# Remove app_offline so the app comes back on next request
Remove-Item $appOffline -ErrorAction SilentlyContinue

Write-Host "==> Deployment complete."
