<#
.SYNOPSIS
  QQ 邮箱专属入口 (qq_number@qq.com)
.DESCRIPTION
  QQ 邮箱操作脚本。
  详细参考手册请查阅: references\qq.md
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$engine = Join-Path $scriptDir "core\mail-engine.ps1"

& powershell -ExecutionPolicy Bypass -File $engine -Account qq @args
exit $LASTEXITCODE
