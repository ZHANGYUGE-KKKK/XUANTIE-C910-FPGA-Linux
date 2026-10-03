$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'vendor/coremark-pro-main'
$manifest = @(Import-Csv (Join-Path $PSScriptRoot 'vendor.sha256.csv'))
if (-not $manifest.Count) { throw 'Empty upstream manifest' }
foreach ($file in $manifest) {
    $path = Join-Path $root $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing upstream file: $($file.path)" }
    $stream = [IO.File]::OpenRead($path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','') }
    finally { $stream.Dispose(); $hasher.Dispose() }
    if ($digest -ne $file.sha256) {
        throw "Upstream file changed: $($file.path)"
    }
}
Write-Host "Upstream verified: $($manifest.Count) original files (commit 4832cc67b0926c7a80a4b7ce0ce00f4640ea6bec)"
