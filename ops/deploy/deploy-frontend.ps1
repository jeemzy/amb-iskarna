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

$dockerHost = 'tcp://192.168.88.130:2375'
$candidates = @(
  'apps/frontend/docker-compose.yml',
  'apps/frontend/docker-compose.yaml',
  'apps/frontend/compose.yml',
  'apps/frontend/compose.yaml',
  'ops/docker/frontend/docker-compose.yml',
  'ops/docker/frontend/docker-compose.yaml',
  'ops/docker/frontend.compose.yml',
  'ops/docker/frontend.compose.yaml',
  'docker-compose.frontend.yml',
  'docker-compose.frontend.yaml'
)

Write-Section 'Frontend deploy: validate remote Docker access'
Write-Host "Repository root: $repoRoot"
Write-Host "Remote Docker host: $dockerHost"
docker -H $dockerHost version
Close-Section

Write-Section 'Frontend deploy: resolve compose file'
$composeRelative = $null
foreach ($candidate in $candidates) {
  $fullPath = Join-Path $repoRoot $candidate
  if (Test-Path $fullPath) {
    $composeRelative = $candidate
    break
  }
}

if (-not $composeRelative) {
  throw "No frontend compose file was found. Checked: $($candidates -join ', ')"
}

$composeFullPath = Join-Path $repoRoot $composeRelative
Write-Host "Using compose file: $composeRelative"
Close-Section

Write-Section 'Frontend deploy: validate compose configuration'
docker -H $dockerHost compose -f $composeFullPath config --quiet
Close-Section

Write-Section 'Frontend deploy: stop current frontend stack'
Write-Host 'Running docker compose down without -v so volumes are preserved.'
docker -H $dockerHost compose -f $composeFullPath down
Close-Section

Write-Section 'Frontend deploy: build and start new frontend stack'
docker -H $dockerHost compose -f $composeFullPath up -d --build
Close-Section

Write-Section 'Frontend deploy: current frontend stack state'
docker -H $dockerHost compose -f $composeFullPath ps
Close-Section

Add-Summary '# Frontend deployment'
Add-Summary ''
Add-Summary "- Remote Docker host: $dockerHost"
Add-Summary "- Compose file: $composeRelative"
Add-Summary '- Lifecycle commands executed:'
Add-Summary '  - docker -H tcp://192.168.88.130:2375 compose ... down'
Add-Summary '  - docker -H tcp://192.168.88.130:2375 compose ... up -d --build'

Write-Host '::notice::Frontend deployment completed successfully.'
