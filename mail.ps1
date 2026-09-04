<#
.SYNOPSIS
  统一邮件工具箱入口 (Unified Mail Gateway)
.DESCRIPTION
  顶层快速发信与多通道调度入口。
  底层统一调用 mail-service\core\mail-engine.ps1。
  
  通道支持：
    - edu: 高校校园邮箱 (student_id@your_school.edu.cn)
    - qq: QQ 邮箱 (qq_number@qq.com)
    - netease / 163: 网易 163 邮箱 (username@163.com)
    - fmail / cf: Cloudflare 临时邮箱 (Fmail)

  业务扩展：
    - batch-send / 套磁信: 批量高校学术套磁信发送
    - track: 套磁信跟进状态追踪

  安全红线：
    1. ⛔ 永远禁止删除任何邮件。
    2. ⚠️ 发信必须显式提供 --via <channel>，严禁擅自猜测或自动兜底。
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:PROJECT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:ENGINE = Join-Path $script:PROJECT_ROOT "mail-service\core\mail-engine.ps1"

function Show-Help {
    Write-Host ""
    Write-Host "  Unified Mail Tool — Edu | QQ | NetEase 163 | Fmail" -ForegroundColor Cyan
    Write-Host "  Engine: mail-service\core\mail-engine.ps1" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    .\mail.ps1 <command> [--via edu|qq|netease|fmail] [options]"
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host "    test                测试各通道连通性"
    Write-Host "    check               查看收件箱 (--via 指定通道，默认 edu)"
    Write-Host "    search              搜索邮件"
    Write-Host "    fetch               查看邮件详情全文 (fetch <UID>)"
    Write-Host "    download            下载邮件附件 (download <UID>)"
    Write-Host "    send                发送邮件 (必须提供 --via edu|qq|netease)"
    Write-Host "    mark-read           标记为已读"
    Write-Host "    mark-unread         标记为未读"
    Write-Host "    list-mailboxes      列出所有文件夹"
    Write-Host "    stats               查看文件夹统计
    ui                  启动本地 Web 控制台 (前后端分离)"
    Write-Host "    cf / fmail          Cloudflare 临时邮箱操作"
    Write-Host "    batch-send / 套磁信  批量学术套磁信发送"
    Write-Host "    track               套磁信状态跟踪"
    Write-Host ""
    Write-Host "  发信选项:" -ForegroundColor White
    Write-Host "    --via <channel>     必填发信通道 (edu | qq | netease)"
    Write-Host "    --to <addr>         收件人地址"
    Write-Host "    --subject <text>    邮件主题"
    Write-Host "    --body <text>       正文内容"
    Write-Host "    --attach <file>     附件文件路径"
    Write-Host "    --html              启用 HTML 正文"
    Write-Host "    --no-sig            不追加默认签名"
    Write-Host "    --draft             保存为草稿不发送"
    Write-Host "    --schedule <time>   定时发送（如 '2026-09-05 09:00'）"
    Write-Host ""
}

$allArgs = @($args)
if ($allArgs.Count -eq 0) { Show-Help; exit 0 }

$command = $allArgs[0].ToLower()
$restArgs = @($allArgs | Select-Object -Skip 1)

# 提取 --via 参数
$via = ""
$filteredArgs = @()
$i = 0
while ($i -lt $restArgs.Count) {
    if ($restArgs[$i] -in @("--via", "-via") -and $i + 1 -lt $restArgs.Count) {
        $via = $restArgs[$i + 1].ToLower()
        $i += 2
    } else {
        $filteredArgs += $restArgs[$i]
        $i++
    }
}

# 规范化别名
if ($via -in @("163", "wangyi", "netease-mail")) { $via = "netease" }
if ($via -in @("qq-mail")) { $via = "qq" }
if ($via -in @("campus-mail", "campus", "school", "edu-mail")) { $via = "edu" }
if ($via -in @("cf", "temp", "temp-mail")) { $via = "fmail" }

switch ($command) {

    { $_ -in @("ui", "web", "dashboard") } {
        $serverScript = Join-Path $script:PROJECT_ROOT "web\server.py"
        & python $serverScript --open @filteredArgs
        exit $LASTEXITCODE
    }

    "test" {
        if ($via) {
            & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $via test @filteredArgs
        } else {
            Write-Host "=== 1. 高校校园邮箱通道测试 ===" -ForegroundColor Cyan
            & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account edu test
            Start-Sleep -Milliseconds 800

            Write-Host ""
            Write-Host "=== 2. QQ 邮箱通道测试 ===" -ForegroundColor Cyan
            & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account qq test
            Start-Sleep -Milliseconds 800

            Write-Host ""
            Write-Host "=== 3. 网易 163 邮箱通道测试 ===" -ForegroundColor Cyan
            & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account netease test
            Start-Sleep -Milliseconds 800

            Write-Host ""
            Write-Host "=== 4. Cloudflare 临时邮箱测试 (Fmail) ===" -ForegroundColor Cyan
            $fmailScript = Join-Path $script:PROJECT_ROOT "fmail\fmail.ps1"
            if (Test-Path $fmailScript) {
                & powershell -ExecutionPolicy Bypass -File $fmailScript domains
            }
        }
    }

    "send" {
        # 严格强制通道显式确认
        if (-not $via) {
            Write-Host ""
            Write-Host "=================================================================" -ForegroundColor Red
            Write-Host "[ERROR] 发信必须显式指定发信邮箱通道！" -ForegroundColor Red
            Write-Host "请在发信命令中添加 --via <edu|qq|netease>。" -ForegroundColor Yellow
            Write-Host "若未确认通道，请先向主人询问确认希望使用哪个邮箱发送，严禁自动代选！" -ForegroundColor Yellow
            Write-Host "=================================================================" -ForegroundColor Red
            Write-Host ""
            exit 1
        }
        if ($via -notin @("edu", "qq", "netease")) {
            Write-Host "[ERROR] 不支持的发信通道: '$via'。仅支持 edu (校园邮箱), qq, netease。" -ForegroundColor Red
            exit 1
        }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $via send @filteredArgs
    }

    { $_ -in @("check", "list") } {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount check @filteredArgs
    }

    "search" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount search @filteredArgs
    }

    "fetch" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount fetch @filteredArgs
    }

    "download" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount download @filteredArgs
    }

    "mark-read" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount mark-read @filteredArgs
    }

    "mark-unread" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount mark-unread @filteredArgs
    }

    "list-mailboxes" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount list-mailboxes @filteredArgs
    }

    "stats" {
        $targetAccount = if ($via) { $via } else { "edu" }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $targetAccount stats @filteredArgs
    }

    { $_ -in @("draft", "drafts", "list-drafts", "send-draft") } {
        $draftScript = Join-Path $script:PROJECT_ROOT "mail-service\core/draft-manager.ps1"
        $viaParam = if ($via) { @("--via", $via) } else { @("--via", "edu") }
        if ($command -eq "send-draft") {
            & powershell -ExecutionPolicy Bypass -File $draftScript "send" @filteredArgs @viaParam
        } elseif ($command -in @("drafts", "list-drafts")) {
            & powershell -ExecutionPolicy Bypass -File $draftScript "list" @filteredArgs @viaParam
        } else {
            & powershell -ExecutionPolicy Bypass -File $draftScript @filteredArgs @viaParam
        }
    }

    { $_ -in @("attach", "attachments") } {
        $attScript = Join-Path $script:PROJECT_ROOT "套磁信\core\engine/attachment-manager.ps1"
        & powershell -ExecutionPolicy Bypass -File $attScript @filteredArgs
    }

    { $_ -in @("scan", "mailbox-scan") } {
        $scanScript = Join-Path $script:PROJECT_ROOT "mail-service\core/mailbox-inspector.ps1"
        $viaParam = if ($via) { @("--via", $via) } else { @("--via", "edu") }
        & powershell -ExecutionPolicy Bypass -File $scanScript "scan" @filteredArgs @viaParam
    }

    { $_ -in @("search-all", "deep-search") } {
        $scanScript = Join-Path $script:PROJECT_ROOT "mail-service/core/mailbox-inspector.ps1"
        $viaParam = if ($via) { @("--via", $via) } else { @("--via", "edu") }
        & powershell -ExecutionPolicy Bypass -File $scanScript "search-all" @filteredArgs @viaParam
    }

    { $_ -in @("doctor", "check-all", "diagnose") } {
        $doctorScript = Join-Path $script:PROJECT_ROOT "mail-service/core/system-doctor.ps1"
        & powershell -ExecutionPolicy Bypass -File $doctorScript @filteredArgs
    }

    { $_ -in @("check-mentor", "mentor-check") } {
        $mentorScript = Join-Path $script:PROJECT_ROOT "套磁信/core/engine/mentor-checker.ps1"
        & powershell -ExecutionPolicy Bypass -File $mentorScript @filteredArgs
    }

    { $_ -in @("cf", "fmail") } {
        $fmailScript = Join-Path $script:PROJECT_ROOT "fmail\fmail.ps1"
        if (Test-Path $fmailScript) {
            & powershell -ExecutionPolicy Bypass -File $fmailScript @filteredArgs
        } else {
            Write-Host "[ERROR] 未找到 Fmail 脚本: $fmailScript" -ForegroundColor Red
        }
    }

    { $_ -in @("batch-send", "taoci", "套磁", "套磁信") } {
        $batchScript = Join-Path $script:PROJECT_ROOT "套磁信\scripts\batch-send.ps1"
        if (Test-Path $batchScript) {
            & powershell -ExecutionPolicy Bypass -File $batchScript @filteredArgs
        } else {
            Write-Host "[ERROR] 未找到套磁信批量发送脚本: $batchScript" -ForegroundColor Red
        }
    }

    "track" {
        $trackScript = Join-Path $script:PROJECT_ROOT "套磁信\scripts\track-mail.ps1"
        if (Test-Path $trackScript) {
            & powershell -ExecutionPolicy Bypass -File $trackScript @filteredArgs
        } else {
            Write-Host "[ERROR] 未找到套磁信追踪脚本: $trackScript" -ForegroundColor Red
        }
    }

    default {
        Write-Host "[ERROR] 未知命令: '$command'" -ForegroundColor Red
        Show-Help
        exit 1
    }
}
