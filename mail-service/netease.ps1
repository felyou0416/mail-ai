<#
.SYNOPSIS
  网易 163 邮箱专属入口 (username@163.com)
.DESCRIPTION
  网易 163 邮箱操作脚本。
  详细参考手册请查阅: references\netease.md
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$engine = Join-Path $scriptDir "core\mail-engine.ps1"

& powershell -ExecutionPolicy Bypass -File $engine -Account netease @args
exit $LASTEXITCODE
