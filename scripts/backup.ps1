param(
  [string]$SiteName = "Site1",
  [string]$SitePath = "\\GITHUB-ACTION\Site1",
  [string]$BackupRoot = "\\GITHUB-ACTION\IIS-Backup"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "${SiteName}-${timestamp}"
$siteZip = Join-Path $BackupRoot "$backupName-content.zip"
$configTag = $backupName  # Used by appcmd

# Ensure backup directory exists
New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null

Write-Host "==> Zipping site content from $SitePath to $siteZip"
if (Test-Path $SitePath) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path $siteZip) { Remove-Item $siteZip -Force }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($SitePath, $siteZip)
} else {
  Write-Warning "Site path not found: $SitePath (skipping content backup)"
}

Write-Host "==> Backing up IIS configuration via appcmd: $configTag"
$inetsrv = "$env:SystemRoot\System32\inetsrv"
& "$inetsrv\appcmd.exe" add backup "$configTag" | Write-Host

# Output metadata JSON
$meta = @{
  SiteName     = $SiteName
  SitePath     = $SitePath
  BackupRoot   = $BackupRoot
  SiteZip      = $siteZip
  ConfigBackup = $configTag
  CreatedAt    = (Get-Date)
}
$metaPath = Join-Path $BackupRoot "$backupName.json"
$meta | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8

Write-Host "==> Backup complete: $backupName"
