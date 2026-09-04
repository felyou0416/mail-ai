<#
.SYNOPSIS
  Mail-AI 启动本地 Web 控制台 (前后端分离架构)
.DESCRIPTION
  启动本地 REST API 服务并自动在默认浏览器中打开控制台界面。
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$serverScript = Join-Path $scriptDir "web\server.py"

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  正在启动 Mail-AI 本地 Web 控制台 (前后端分离)..." -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

& python $serverScript --open @args
