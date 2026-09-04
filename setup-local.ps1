<#
.SYNOPSIS
  Mail-AI 本地环境快速初始化与私密配置向导 (Local Setup Assistant)
.DESCRIPTION
  为本地用户或新克隆者提供一键式初始化：
  1. 检查 Python 3 与 Node.js 运行时
  2. 自动由 sample 样板创建本地私有配置文件 (profile.json, signature.html)
  3. 执行全系统综合体检
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:PROJECT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       Mail-AI 本地私密环境初始化向导 (Setup Local)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. 检查 Python
Write-Host "[1/4] 检查 Python 运行环境 ... " -NoNewline
try {
    $pyVer = & python --version 2>&1
    Write-Host "[正常 ✓] ($pyVer)" -ForegroundColor Green
} catch {
    Write-Host "[未找到 ✗] 请安装 Python 3.8+ 并添加至 PATH" -ForegroundColor Red
}

# 2. 检查 Node.js
Write-Host "[2/4] 检查 Node.js 运行环境 ... " -NoNewline
try {
    $nodeVer = & node --version 2>&1
    Write-Host "[正常 ✓] ($nodeVer)" -ForegroundColor Green
} catch {
    Write-Host "[未找到 ✗] 请安装 Node.js 16+ 并添加至 PATH" -ForegroundColor Red
}

# 3. 自动初始化各邮箱 Profile 与签名
Write-Host "[3/4] 检查并初始化本地私密配置文件 (自动防 Git 泄露) ... " -ForegroundColor White

foreach ($acc in @("edu", "qq", "netease")) {
    $pDir = Join-Path $script:PROJECT_ROOT "mail-service\profiles\$acc"
    if (-not (Test-Path $pDir)) { New-Item -ItemType Directory -Path $pDir -Force | Out-Null }
    
    $pJson = Join-Path $pDir "profile.json"
    $sJson = Join-Path $pDir "profile.sample.json"
    if ((-not (Test-Path $pJson)) -and (Test-Path $sJson)) {
        Copy-Item $sJson $pJson
        Write-Host "  - [$acc] 已由模版生成私有配置: $pJson" -ForegroundColor Yellow
    } else {
        Write-Host "  - [$acc] 配置文件已就绪 ✓" -ForegroundColor Green
    }

    $sHtml = Join-Path $pDir "signature.html"
    $sampleHtml = Join-Path $pDir "signature.sample.html"
    if ((-not (Test-Path $sHtml)) -and (Test-Path $sampleHtml)) {
        Copy-Item $sampleHtml $sHtml
        Write-Host "  - [$acc] 已由模版生成私有签名: $sHtml" -ForegroundColor Yellow
    }
}

# 4. 执行综合体检
Write-Host ""
Write-Host "[4/4] 启动全系统综合体检 ..." -ForegroundColor White
$docScript = Join-Path $script:PROJECT_ROOT "mail-service\core\system-doctor.ps1"
& powershell -ExecutionPolicy Bypass -File $docScript

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 本地环境初始化完成！" -ForegroundColor Green
Write-Host " 快速使用指令：" -ForegroundColor White
Write-Host "   1. 启动 Web 可视化控制台:  .\ui.ps1  或  .\mail.ps1 ui" -ForegroundColor Yellow
Write-Host "   2. 命令行系统体检:        .\mail.ps1 doctor" -ForegroundColor Yellow
Write-Host "   3. 查看当前草稿:          .\mail.ps1 draft list" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
