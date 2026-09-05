[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$engine = Join-Path (Split-Path -Parent $PSScriptRoot) "core\engine\track-mail.ps1"
& powershell -ExecutionPolicy Bypass -File $engine @args
