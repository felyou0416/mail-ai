<#
.SYNOPSIS
  全邮箱健康与垃圾邮件一键巡检器 (Mailbox Inspector)
.DESCRIPTION
  一键快速巡检指定邮箱或所有邮箱：
  - scan              一键扫描 INBOX、草稿箱、垃圾邮件、广告邮件的状态
  - search-all <词>   跨所有关键文件夹执行关键词检索（防止通知漏网）
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:CORE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:SERVICE_DIR = Split-Path -Parent $script:CORE_DIR
$script:IMAP_SCRIPT = Join-Path $script:CORE_DIR "imap.bundle.js"
$script:ENGINE = Join-Path $script:CORE_DIR "mail-engine.ps1"

$account = "edu"
$action = "scan"
$keyword = ""
$isJson = $false

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "-Json" { $isJson = $true }
        "--json" { $isJson = $true }
        "--via" { $account = $args[++$i].ToLower(); if ($account -in @("campus","school")) { $account = "edu" } }
        default {
            if (-not $action -or $action -eq "scan") {
                if ($args[$i] -in @("scan", "search-all", "deep-search")) {
                    $action = $args[$i]
                } elseif (-not $keyword) {
                    $keyword = $args[$i]
                }
            } elseif (-not $keyword) {
                $keyword = $args[$i]
            }
        }
    }
    $i++
}

if ($account -in @("163", "wangyi")) { $account = "netease" }

switch ($action) {
    "scan" {
        Write-Host ""
        Write-Host "=== [$account 邮箱] 全文件夹状态一键健康巡检 ===" -ForegroundColor Cyan

        # 提取当前邮箱支持的文件夹
        $boxesRaw = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $account list-mailboxes 2>$null
        $boxes = $boxesRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

        if (-not $boxes) {
            Write-Host "[ERROR] 无法获取 $account 邮箱的文件夹列表，请检查网络或凭证。" -ForegroundColor Red
            exit 1
        }

        # 重点排查的文件夹名单
        $targetFolders = @("INBOX", "收件箱", "草稿箱", "Drafts", "垃圾邮件", "Junk", "广告邮件", "病毒文件夹", "质谱")
        
        Write-Host "文件夹名称".PadRight(18) + "邮件状态".PadRight(20) + "诊断与建议" -ForegroundColor White
        Write-Host ("-" * 60) -ForegroundColor DarkGray

        foreach ($box in $boxes) {
            $name = $box.name
            $isTarget = $false
            foreach ($t in $targetFolders) {
                if ($name -like "*$t*") { $isTarget = $true; break }
            }
            if (-not $isTarget) { continue }

            # 快速 check 1 封，看数量或最新
            $checkOut = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $account check --mailbox "$name" --limit 1 2>$null
            $mails = $checkOut | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            $countStr = if ($mails -and @($mails).Count -gt 0) { "存在邮件 (有最新)" } else { "当前为空 (0 封)" }
            $statusColor = if ($mails -and @($mails).Count -gt 0) {
                if ($name -match '(垃圾|Junk|广告)') { "Yellow" } else { "Green" }
            } else { "DarkGray" }

            $tip = ""
            if ($name -match '(垃圾|Junk|广告)' -and $mails -and @($mails).Count -gt 0) {
                $tip = "⚠️ 存在邮件，建议查看是否有推免通知被误拦"
            } elseif ($name -match '(草稿|Draft)' -and $mails -and @($mails).Count -gt 0) {
                $tip = "待发草稿已就绪"
            } elseif ($name -eq "INBOX" -or $name -eq "收件箱") {
                $tip = "正常收件通信"
            }

            Write-Host $name.PadRight(18) -NoNewline -ForegroundColor White
            Write-Host $countStr.PadRight(20) -NoNewline -ForegroundColor $statusColor
            Write-Host $tip -ForegroundColor $statusColor
        }
        Write-Host ("-" * 60) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  查看特定箱: .\mail.ps1 check --via $account --mailbox <文件夹名>" -ForegroundColor DarkCyan
        Write-Host "  全文件夹搜: .\mail.ps1 search-all <关键词> --via $account" -ForegroundColor DarkCyan
        Write-Host ""
    }

    { $_ -in @("search-all", "deep-search") } {
        if (-not $keyword) {
            Write-Host "[ERROR] 请提供搜索关键词！用法: .\mail.ps1 search-all <关键词> --via $account" -ForegroundColor Red
            exit 1
        }
        Write-Host ""
        Write-Host "=== 正在 [$account 邮箱] 全文件夹深度扫描: '$keyword' ===" -ForegroundColor Cyan
        
        $scanBoxes = if ($account -in @("edu")) {
            @("INBOX", "广告邮件", "垃圾邮件", "质谱", "草稿箱")
        } elseif ($account -eq "qq") {
            @("INBOX", "Junk", "Drafts")
        } else {
            @("INBOX", "广告邮件", "垃圾邮件", "草稿箱")
        }

        $totalFound = 0
        foreach ($b in $scanBoxes) {
            Write-Host "  [SCAN] 正在检索文件夹: $b ..." -ForegroundColor DarkGray
            $res = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $account search --subject "$keyword" --mailbox "$b" --limit 5 2>$null
            $mails = $res | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($mails -and @($mails).Count -gt 0) {
                foreach ($m in $mails) {
                    Write-Host "  [FOUND in $b] UID: $($m.uid)" -ForegroundColor Yellow
                    Write-Host "      发件人: $($m.from)" -ForegroundColor White
                    Write-Host "      主  题: $($m.subject)" -ForegroundColor Cyan
                    Write-Host "      时  间: $($m.date)" -ForegroundColor DarkGray
                    $totalFound++
                }
            }
        }

        if ($totalFound -eq 0) {
            Write-Host "  未在任何文件夹中检索到包含 '$keyword' 的邮件。" -ForegroundColor Yellow
        } else {
            Write-Host "  共找到 $totalFound 封匹配邮件。" -ForegroundColor Green
        }
        Write-Host ""
    }
}
