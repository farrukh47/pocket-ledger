$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    flutter create --platforms=android --org com.farrukh --project-name pocket_ledger --no-pub .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter scaffold failed.' }
    if (Test-Path test/widget_test.dart) { Remove-Item test/widget_test.dart }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency download failed.' }
} finally { Pop-Location }
