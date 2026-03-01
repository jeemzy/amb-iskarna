# Amb-Iskarna backend runner with auto-restart.
# This script is started by Task Scheduler at logon and keeps
# uvicorn alive by restarting it if it crashes.

$stateRoot = Join-Path $env:LOCALAPPDATA 'AmbIskarna'
$logsRoot  = Join-Path $stateRoot 'logs'
$venvPy    = Join-Path $stateRoot '.venv\Scripts\python.exe'
$pidFile   = Join-Path $stateRoot 'backend.pid'

$restartDelay = 5  # seconds between restart attempts

# Resolve repo root (written by deploy script)
$repoRootFile = Join-Path $stateRoot 'repo_root.txt'
if (-not (Test-Path $repoRootFile)) {
  Write-Host "ERROR: $repoRootFile not found. Run the deploy script first."
  exit 1
}
$repoRoot = (Get-Content $repoRootFile -Raw).Trim()

# Resolve app module (written by deploy script)
$appModuleFile = Join-Path $stateRoot 'app_module.txt'
if (-not (Test-Path $appModuleFile)) {
  Write-Host "ERROR: $appModuleFile not found. Run the deploy script first."
  exit 1
}
$appModule = (Get-Content $appModuleFile -Raw).Trim()

New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

while ($true) {
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$timestamp] Starting uvicorn: $appModule"

  $proc = Start-Process -FilePath $venvPy `
    -ArgumentList @('-m', 'uvicorn', $appModule, '--host', '0.0.0.0', '--port', '8765') `
    -WorkingDirectory $repoRoot `
    -PassThru -NoNewWindow

  Set-Content -Path $pidFile -Value $proc.Id -NoNewline
  Write-Host "[$timestamp] PID: $($proc.Id)"

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$timestamp] uvicorn exited with code $exitCode"

  if (Test-Path $pidFile) { Remove-Item $pidFile -Force }

  Write-Host "[$timestamp] Restarting in $restartDelay seconds..."
  Start-Sleep -Seconds $restartDelay
}
