$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path dist | Out-Null
$env:CGO_ENABLED = '0'
$env:GOOS = 'windows'
foreach ($arch in @('amd64', 'arm64')) {
    $env:GOARCH = $arch
    go build -trimpath -buildvcs=false -ldflags '-s -w -H=windowsgui' -o "dist/MoleDesk-windows-$arch.exe" ./cmd/mandesk
    if ($LASTEXITCODE -ne 0) { throw "Windows $arch build failed" }
}
