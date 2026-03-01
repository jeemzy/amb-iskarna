$ErrorActionPreference = 'Stop'

function Write-Section([string]$Title) {
  Write-Host "::group::$Title"
}

function Close-Section {
  Write-Host '::endgroup::'
}

function Add-Summary([string]$Line) {
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Line
  }
}

$repoRoot = $env:GITHUB_WORKSPACE
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
  $repoRoot = (Get-Location).Path
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'AmbIskarna'
$logsRoot = Join-Path $stateRoot 'logs'
$venvRoot = Join-Path $stateRoot '.venv'
$pidFile = Join-Path $stateRoot 'backend.pid'
$stdoutLog = Join-Path $logsRoot 'backend.stdout.log'
$stderrLog = Join-Path $logsRoot 'backend.stderr.log'

$backendDir = $null
foreach ($candidate in @('apps/backend', 'backend')) {
  $fullPath = Join-Path $repoRoot $candidate
  if (Test-Path $fullPath) {
    $backendDir = $fullPath
    break
  }
}

if (-not $backendDir) {
  throw 'Backend directory was not found. Expected apps/backend or backend.'
}

$appModule = $null
if (Test-Path (Join-Path $repoRoot 'apps/backend/main.py')) {
  $appModule = 'apps.backend.main:app'
}
elseif (Test-Path (Join-Path $repoRoot 'apps/backend/app/main.py')) {
  $appModule = 'apps.backend.app.main:app'
}
elseif (Test-Path (Join-Path $repoRoot 'backend/main.py')) {
  $appModule = 'backend.main:app'
}
else {
  throw 'A FastAPI entrypoint was not found. Expected apps/backend/main.py, apps/backend/app/main.py, or backend/main.py.'
}

Write-Section 'Backend deploy: prepare local state directories'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
Write-Host "Repository root: $repoRoot"
Write-Host "Backend directory: $backendDir"
Write-Host "State root: $stateRoot"
Write-Host "Logs root: $logsRoot"
Write-Host "FastAPI app module: $appModule"
Close-Section

$venvPython = Join-Path $venvRoot 'Scripts/python.exe'
$taskName = 'AmbIskarnaBackend'

Write-Section 'Backend deploy: stop running backend processes'
# Clean up NSSM service if it exists from previous deploy approach
$nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
if ($nssmCmd) {
  $nssmStatus = nssm status AmbIskarnaBackend 2>&1
  if ($nssmStatus -notmatch 'Can.t open service') {
    Write-Host 'Stopping and removing legacy NSSM service...'
    nssm stop AmbIskarnaBackend 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    nssm remove AmbIskarnaBackend confirm 2>&1 | Out-Null
    Write-Host 'Removed NSSM service AmbIskarnaBackend'
  }
}

# Kill any existing backend process via PID file
if (Test-Path $pidFile) {
  $existingPid = (Get-Content $pidFile -Raw).Trim()
  if ($existingPid) {
    Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped process $existingPid"
  }
  Remove-Item $pidFile -Force
}

# Stop the scheduled task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  Write-Host "Removed existing task: $taskName"
}

# Kill any lingering python processes from the venv
if (Test-Path $venvPython) {
  Get-Process python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $venvPython } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}
Close-Section

Write-Section 'Backend deploy: create or reuse Python virtual environment'

$pyCmd = $null
$usePyLauncher = $false

# Try py / python3 / python from PATH
foreach ($name in @('py', 'python3', 'python')) {
  $found = Get-Command $name -ErrorAction SilentlyContinue
  if ($found) {
    $pyCmd = $found.Source
    if ($name -eq 'py') { $usePyLauncher = $true }
    Write-Host "Found $name at $($found.Source)"
    break
  }
}

if (-not $pyCmd) {
  Write-Host 'Python was not found in PATH (tried: py, python3, python).'
  throw 'Python was not found on the self-hosted runner.'
}

if (Test-Path $venvRoot) {
  Write-Host "Removing existing virtual environment at $venvRoot"
  Remove-Item -Recurse -Force $venvRoot
}

Write-Host "Creating fresh virtual environment at $venvRoot"
if ($usePyLauncher) {
  & $pyCmd -3.12 -m venv $venvRoot
}
else {
  & $pyCmd -m venv $venvRoot
}

$venvPython = Join-Path $venvRoot 'Scripts/python.exe'
if (-not (Test-Path $venvPython)) {
  throw "Virtual environment python executable was not found at $venvPython"
}

& $venvPython -m pip install --upgrade pip
Close-Section

Write-Section 'Backend deploy: install backend dependencies'
$requirementsFile = Join-Path $backendDir 'requirements.txt'
$pyprojectFile = Join-Path $backendDir 'pyproject.toml'

if (Test-Path $requirementsFile) {
  Write-Host "Installing from requirements file: $requirementsFile"
  & $venvPython -m pip install -r $requirementsFile
}
elseif (Test-Path $pyprojectFile) {
  Write-Host "Installing editable package from: $backendDir"
  & $venvPython -m pip install -e $backendDir
}
else {
  throw 'No backend dependency manifest found. Expected requirements.txt or pyproject.toml in the backend directory.'
}
Close-Section

Write-Section 'Backend deploy: save runtime config for wrapper script'
# The wrapper script reads these at startup
Set-Content -Path (Join-Path $stateRoot 'repo_root.txt') -Value $repoRoot -NoNewline
Set-Content -Path (Join-Path $stateRoot 'app_module.txt') -Value $appModule -NoNewline
$wrapperScript = Join-Path $repoRoot 'ops/deploy/run-backend.ps1'
Write-Host "Wrapper script: $wrapperScript"
Write-Host "Repo root: $repoRoot"
Write-Host "App module: $appModule"
Close-Section

Write-Section 'Backend deploy: register scheduled task'
$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwshPath) { $pwshPath = 'powershell.exe' }

$action = New-ScheduledTaskAction `
  -Execute $pwshPath `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperScript`"" `
  -WorkingDirectory $repoRoot

$trigger = New-ScheduledTaskTrigger -AtLogon
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask `
  -TaskName $taskName `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Settings $settings `
  -Description 'Amb-Iskarna backend (uvicorn with auto-restart)' `
  -Force | Out-Null

Write-Host "Registered task: $taskName"
Write-Host "  Runs as: $env:USERNAME (interactive session)"
Write-Host "  Trigger: at logon"
Write-Host "  Script: $wrapperScript"
Close-Section

Write-Section 'Backend deploy: start task now'
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
$taskInfo = Get-ScheduledTask -TaskName $taskName
Write-Host "Task state: $($taskInfo.State)"
Close-Section

Write-Section 'Backend deploy: health check'
$healthUrl = 'http://127.0.0.1:8765/api/health'
$healthy = $false
for ($attempt = 1; $attempt -le 20; $attempt++) {
  try {
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3
    if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
      Write-Host "Health check succeeded on attempt $attempt with status $($response.StatusCode)"
      $healthy = $true
      break
    }
  }
  catch {
    Write-Host "Health check attempt $attempt failed: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 2
}

if (-not $healthy) {
  if (Test-Path $stderrLog) {
    Write-Host 'Last backend stderr output:'
    Get-Content $stderrLog -Tail 200
  }
  throw "Backend health check never succeeded at $healthUrl"
}
Close-Section

Add-Summary '# Backend deployment'
Add-Summary ''
Add-Summary "- Task name: $taskName"
Add-Summary "- Runs as: $env:USERNAME (interactive desktop session)"
Add-Summary "- Backend directory: $($backendDir.Replace($repoRoot + '\', ''))"
Add-Summary "- FastAPI module: $appModule"
Add-Summary "- Health check: $healthUrl"
Add-Summary "- Wrapper script: $wrapperScript"

Write-Host '::notice::Backend deployment completed successfully.'
