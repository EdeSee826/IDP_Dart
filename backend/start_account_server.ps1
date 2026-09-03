$ErrorActionPreference = "Stop"

$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $BackendDir
$ReuseSitePackages = Join-Path $BackendDir ".venv\Lib\site-packages"
$Python310 = Join-Path $env:LOCALAPPDATA "Programs\Python\Python310\python.exe"
$BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$ProjectVenvPython = Join-Path $BackendDir ".venv\Scripts\python.exe"

try {
    $health = Invoke-RestMethod -Uri "http://localhost:5000/api/health" -TimeoutSec 2
    if ($health.status -eq "ok") {
        Write-Host "Account server is already running at http://localhost:5000"
        exit 0
    }
} catch {
    # Server is not running yet.
}

if (Test-Path -LiteralPath $Python310) {
    $PythonExe = $Python310
} elseif (Test-Path -LiteralPath $ProjectVenvPython) {
    $PythonExe = $ProjectVenvPython
} elseif (Test-Path -LiteralPath $BundledPython) {
    $PythonExe = $BundledPython
    if (Test-Path -LiteralPath $ReuseSitePackages) {
        $env:PYTHONPATH = $ReuseSitePackages
    }
} else {
    $PythonExe = "python"
}

Write-Host "Starting account server at http://localhost:5000"
Write-Host "Backend folder: $BackendDir"
Set-Location $BackendDir
& $PythonExe "run.py"
