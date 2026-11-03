# Copyright 2026 Noverberrain.
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

function Get-InterfaceFingerprints {
    $interfacePaths = @(git ls-files --cached --others --exclude-standard -- '*.mbti')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list interface files' }
    (($interfacePaths | Sort-Object -Unique | ForEach-Object {
        "$_ $((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash)"
    }) -join "`n")
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    python -X utf8 scripts/verify_fixtures.py
    if ($LASTEXITCODE -ne 0) { throw 'Fixture identity checks failed' }
    moon fmt --check
    if ($LASTEXITCODE -ne 0) { throw 'Formatting check failed' }
    moon check --target native --warn-list +unnecessary_annotation
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit check failed' }
    moon test --target native
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit tests failed' }
    moon build --target native
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit build failed' }
    python -X utf8 scripts/test_cli.py --exe _build/native/debug/build/cmd/main/main.exe --example _build/native/debug/build/examples/parse/parse.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native CLI process checks failed' }
    python -X utf8 scripts/test_export.py --exe _build/native/debug/build/cmd/main/main.exe
    if ($LASTEXITCODE -ne 0) { throw 'JSONL export process checks failed' }
    $interfacesBefore = Get-InterfaceFingerprints
    moon info --target native
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit interface generation failed' }
    if ($interfacesBefore -cne (Get-InterfaceFingerprints)) {
        throw 'Generated interfaces are out of date; run moon info and review the changes'
    }
} finally {
    Pop-Location
}
