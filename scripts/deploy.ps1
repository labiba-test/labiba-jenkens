param(
  [string]$SiteName = "Site1",
  [string]$AppPool  = "Site1Pool",
  [string]$SitePath = "\\GITHUB-ACTION\Site1",
  [string]$BuildDir = "$PSScriptRoot\..\artifact"
)

Import-Module WebAdministration

Write-Host "==> Stopping app pool $AppPool"
try { Stop-WebAppPool -Name $AppPool -ErrorAction Stop } catch { Write-Warning $_ }

Write-Host "==> Cleaning $SitePath"
if (Test-Path $SitePath) {
  Get-ChildItem $SitePath -Force | Remove-Item -Recurse -Force
} else {
  New-Item -Path $SitePath -ItemType Directory -Force | Out-Null
}

Write-Host "==> Copying new content from $BuildDir to $SitePath"
Copy-Item -Path (Join-Path $BuildDir "*") -Destination $SitePath -Recurse -Force

Write-Host "==> Starting app pool $AppPool"
Start-WebAppPool -Name $AppPool

Write-Host "==> Deploy done for $SiteName"
