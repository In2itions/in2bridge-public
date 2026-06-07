param(
    [string]$Version = "0.0.9",
    [string]$Configuration = "release"
)

$ErrorActionPreference = "Stop"

$releaseRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $releaseRoot "..")
$packagesDir = Join-Path $releaseRoot "packages"
$runtimePayloadDir = Join-Path $releaseRoot "runtime\payload"
$stagingDir = Join-Path $releaseRoot "staging"

New-Item -ItemType Directory -Force -Path $packagesDir | Out-Null
New-Item -ItemType Directory -Force -Path $runtimePayloadDir | Out-Null

Write-Host "Building in2bridge GUI..."
Push-Location (Join-Path $repoRoot "gui")
try {
    npm run build
} finally {
    Pop-Location
}

Write-Host "Building in2bridge engine..."
Push-Location $repoRoot
try {
    cargo build -p in2bridge-engine --release
} finally {
    Pop-Location
}

if (Test-Path $stagingDir) {
    Remove-Item -Recurse -Force $stagingDir
}
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

Write-Host "Preparing release staging area..."
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir "engine") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir "gui") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir "db") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir "runtime") | Out-Null

Copy-Item -Force (Join-Path $repoRoot "target\release\in2bridge-engine.exe") (Join-Path $stagingDir "engine\in2bridge-engine.exe")
Copy-Item -Recurse -Force (Join-Path $repoRoot "gui\dist\*") (Join-Path $stagingDir "gui")
Copy-Item -Recurse -Force (Join-Path $repoRoot "db\migrations") (Join-Path $stagingDir "db")
Copy-Item -Recurse -Force (Join-Path $runtimePayloadDir "*") (Join-Path $stagingDir "runtime") -ErrorAction SilentlyContinue

$manifest = [ordered]@{
    name = "in2bridge"
    version = $Version
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = @(
        "engine/in2bridge-engine.exe",
        "gui",
        "db/migrations",
        "runtime"
    )
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $packagesDir "release-manifest.json")

Write-Host "Release staging completed:"
Write-Host "  $stagingDir"
Write-Host "Manifest:"
Write-Host "  $(Join-Path $packagesDir "release-manifest.json")"
