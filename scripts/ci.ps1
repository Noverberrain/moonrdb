# Copyright 2026 Noverberrain.
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'
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
    moon info --target native
    if ($LASTEXITCODE -ne 0) { throw 'MoonBit interface generation failed' }
    git diff --exit-code -- '*.mbti'
    if ($LASTEXITCODE -ne 0) { throw 'Generated interfaces are out of date' }
} finally {
    Pop-Location
}
