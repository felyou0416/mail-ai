<#
.SYNOPSIS
  高校校园邮箱专属入口 (Edu Mail)
.DESCRIPTION
  高校校园邮箱操作脚本。
  详细参考手册请查阅: references\edu.md
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$engine = Join-Path $scriptDir "core\mail-engine.ps1"

& powershell -ExecutionPolicy Bypass -File $engine -Account edu @args
exit $LASTEXITCODE
