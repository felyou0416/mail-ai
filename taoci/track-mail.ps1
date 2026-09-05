[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$engine = Join-Path $PSScriptRoot "core\engine\track-mail.ps1"
& powershell -ExecutionPolicy Bypass -File $engine @args
