param(
  [string]$SiteName = "Site1",
  [string]$SitePath = "\\GITHUB-ACTION\Site1",
  [string]$BackupRoot = "\\GITHUB-ACTION\IIS-Backup"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "${SiteName}-${timestamp}"
$siteZip = Join-Path $BackupRoot "$backupName-content.zip"
$configTag = $backupName

# Ensure backup directory exists
if (-not (Test-Path $BackupRoot)) {
  Write-Host "==> Creating backup root $BackupRoot"
  New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
}

# Create a temporary folder excluding Jenkins workspace logs
$tempFolder = Join-Path $env:TEMP "$backupName-temp"
if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

Write-Host "==> Copying site content to temp folder for safe backup"
Get-ChildItem -Path $SitePath -Exclude "workspace", "@tmp" | Copy-Item -Destination $tempFolder -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==> Creating ZIP archive at $siteZip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $siteZip) { Remove-Item $siteZip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempFolder, $siteZip)

# Clean up temp folder
Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==> Backing up IIS configuration via appcmd: $configTag"
$inetsrv = "$env:SystemRoot\System32\inetsrv"
& "$inetsrv\appcmd.exe" add backup "$configTag" | Write-Host

# Write metadata
$meta = @{
  SiteName     = $SiteName
  SitePath     = $SitePath
  BackupRoot   = $BackupRoot
  SiteZip      = $siteZip
  ConfigBackup = $configTag
  CreatedAt    = (Get-Date)
}
$meta | ConvertTo-Json | Set-Content (Join-Path $BackupRoot "$backupName.json")

Write-Host "==> Backup complete: $backupName"
