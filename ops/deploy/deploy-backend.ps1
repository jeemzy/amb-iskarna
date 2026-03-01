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

if (-not (Test-Path $venvRoot)) {
  Write-Host "Creating virtual environment at $venvRoot"
  if ($usePyLauncher) {
    & $pyCmd -3.12 -m venv $venvRoot
  }
  else {
    & $pyCmd -m venv $venvRoot
  }
}
else {
  Write-Host "Using existing virtual environment at $venvRoot"
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

Write-Section 'Backend deploy: stop current backend process if present'
if (Test-Path $pidFile) {
  $existingPid = (Get-Content $pidFile | Select-Object -First 1).Trim()
  if (-not [string]::IsNullOrWhiteSpace($existingPid)) {
    $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
    if ($existingProcess) {
      Write-Host "Stopping existing backend process PID $existingPid"
      Stop-Process -Id $existingPid -Force
      Start-Sleep -Seconds 2
    }
    else {
      Write-Host "PID file existed but process $existingPid was not running."
    }
  }
}
else {
  Write-Host 'No existing PID file was found.'
}
Close-Section

Write-Section 'Backend deploy: start backend process'
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }

$arguments = @('-m', 'uvicorn', $appModule, '--host', '0.0.0.0', '--port', '8765')
$process = Start-Process -FilePath $venvPython -ArgumentList $arguments -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -WindowStyle Hidden -PassThru
Set-Content -Path $pidFile -Value $process.Id -NoNewline
Write-Host "Started backend PID $($process.Id)"
Write-Host "stdout log: $stdoutLog"
Write-Host "stderr log: $stderrLog"
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
Add-Summary "- Backend directory: $($backendDir.Replace($repoRoot + '\\', ''))"
Add-Summary "- FastAPI module: $appModule"
Add-Summary "- PID file: $pidFile"
Add-Summary "- Health check: $healthUrl"
Add-Summary "- stdout log: $stdoutLog"
Add-Summary "- stderr log: $stderrLog"

Write-Host '::notice::Backend deployment completed successfully.'
