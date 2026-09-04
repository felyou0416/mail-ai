<#
.SYNOPSIS
  草稿箱专属管家 (Draft Manager)
.DESCRIPTION
  提供快速、安全、免转义的草稿箱限定操作：
  - list        列出所有草稿
  - view <ID>   查看指定草稿的全文与附件
  - clean-test  一键归档测试草稿至 archived 目录（绝不物理删除）
  - send <ID>   发送草稿（带二次确认防误触拦截）
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:CORE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:SERVICE_DIR = Split-Path -Parent $script:CORE_DIR
$script:ENGINE = Join-Path $script:CORE_DIR "mail-engine.ps1"

$account = "edu"
$action = "list"
$target = ""
$confirm = $false
$isJson = $false

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--via" { $account = $args[++$i].ToLower(); if ($account -in @("campus","school")) { $account = "edu" } }
        "--confirm" { $confirm = $true }
        "-Json" { $isJson = $true }
        "--json" { $isJson = $true }
        default {
            if (-not $action -or $action -eq "list") {
                if ($args[$i] -in @("list", "view", "show", "clean", "clean-test", "send")) {
                    $action = $args[$i]
                } elseif (-not $target) {
                    $target = $args[$i]
                }
            } elseif (-not $target) {
                $target = $args[$i]
            }
        }
    }
    $i++
}

if ($account -in @("163", "wangyi")) { $account = "netease" }

$profileDir = Join-Path $script:SERVICE_DIR "profiles\$account"
$draftsDir = Join-Path $profileDir "drafts"

if (-not (Test-Path $draftsDir)) {
    New-Item -ItemType Directory -Path $draftsDir -Force | Out-Null
}

function Get-DraftFiles {
    if (-not (Test-Path $draftsDir)) { return @() }
    return @(Get-ChildItem -Path $draftsDir -Filter "*.json" | Sort-Object LastWriteTime -Descending)
}

function Resolve-DraftFile {
    param([string]$InputTarget)
    $files = Get-DraftFiles
    if ($InputTarget -match '^\d+$') {
        $idx = [int]$InputTarget
        if ($idx -ge 1 -and $idx -le $files.Count) {
            return $files[$idx - 1]
        }
        return $null
    }
    foreach ($f in $files) {
        if ($f.Name -like "*$InputTarget*") {
            return $f
        }
    }
    return $null
}

switch ($action) {
    "list" {
        $files = Get-DraftFiles
        if ($isJson) {
            $items = @()
            $idx = 1
            foreach ($f in $files) {
                try {
                    $d = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $items += @{
                        id = $idx
                        file = $f.Name
                        to = if ($d.Name) { "$($d.Name) <$($d.To)>" } else { [string]$d.To }
                        subject = [string]$d.Subject
                        date = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        attachments = if ($d.Attachments) { @($d.Attachments) } else { @() }
                        is_test = [bool]($d.Subject -like "*测试*" -or $d.To -like "*test*" -or -not $d.To)
                    }
                } catch {}
                $idx++
            }
            $items | ConvertTo-Json -Depth 5 -Compress:$false
            exit 0
        }
        $files = Get-DraftFiles
        Write-Host ""
        Write-Host "=== [$account 邮箱] 本地草稿箱清单 (共 $($files.Count) 封) ===" -ForegroundColor Cyan
        if ($files.Count -eq 0) {
            Write-Host "  当前草稿箱为空。" -ForegroundColor DarkGray
            exit 0
        }
        $idx = 1
        foreach ($f in $files) {
            try {
                $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $toStr = if ($data.Name) { "$($data.Name) <$($data.To)>" } else { [string]$data.To }
                $hasAtt = if ($data.Attachments -and @($data.Attachments).Count -gt 0) { " [📎 附件 $(@($data.Attachments).Count) 个]" } else { "" }
                $isTest = if ($data.Subject -like "*测试*" -or $data.To -like "*test*" -or -not $data.To) { " [⚠️ 测试]" } else { "" }
                
                Write-Host "  [$idx] $toStr" -ForegroundColor Yellow -NoNewline
                Write-Host "$hasAtt$isTest" -ForegroundColor Magenta
                Write-Host "      主题: $($data.Subject)" -ForegroundColor White
                Write-Host "      时间: $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) | 文件: $($f.Name)" -ForegroundColor DarkGray
            } catch {
                Write-Host "  [$idx] $($f.Name) (读取异常)" -ForegroundColor Red
            }
            $idx++
        }
        Write-Host ""
        Write-Host "  查看详情: .\mail.ps1 draft view <序号> --via $account" -ForegroundColor DarkCyan
        Write-Host "  发送草稿: .\mail.ps1 draft send <序号> --via $account --confirm" -ForegroundColor DarkCyan
        Write-Host "  清理测试: .\mail.ps1 draft clean-test --via $account" -ForegroundColor DarkCyan
        Write-Host ""
    }

    { $_ -in @("view", "show") } {
        if (-not $target) { $target = "1" }
        $f = Resolve-DraftFile -InputTarget $target
        if (-not $f) {
            if ($isJson) {
                @{ error = "Draft not found"; target = $target } | ConvertTo-Json
                exit 1
            }
            Write-Host "[ERROR] 未找到序号或关键词对应的草稿: '$target'" -ForegroundColor Red
            exit 1
        }
        $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($isJson) {
            @{
                file = $f.Name
                account = $account
                to = $data.To
                name = $data.Name
                subject = $data.Subject
                body = $data.Body
                attachments = if ($data.Attachments) { @($data.Attachments) } else { @() }
                date = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            } | ConvertTo-Json -Depth 5 -Compress:$false
            exit 0
        }
        Write-Host ""
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host " [DRAFT VIEW] 草稿详情: $($f.Name)" -ForegroundColor White
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "  发信通道: $account" -ForegroundColor DarkGray
        Write-Host "  收 件 人: $($data.To) $(if ($data.Name) { '(' + $data.Name + ')' })" -ForegroundColor White
        Write-Host "  所在单位: $($data.Org)" -ForegroundColor DarkGray
        Write-Host "  邮件主题: $($data.Subject)" -ForegroundColor Cyan
        Write-Host "  创建时间: $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
        if ($data.Attachments -and @($data.Attachments).Count -gt 0) {
            Write-Host "  挂载附件: $(@($data.Attachments) -join '; ')" -ForegroundColor Yellow
        } else {
            Write-Host "  挂载附件: 无" -ForegroundColor DarkGray
        }
        Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "【邮件正文】:" -ForegroundColor Yellow
        if ($data.Body) {
            $data.Body.Split("`n") | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        }
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host ""
    }

    { $_ -in @("clean", "clean-test") } {
        $files = Get-DraftFiles
        $archiveDir = Join-Path $draftsDir "archived"
        if (-not (Test-Path $archiveDir)) {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        }
        $archivedCount = 0
        foreach ($f in $files) {
            try {
                $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $isTest = ($data.Subject -like "*测试*") -or 
                          ($data.Subject -like "*test*") -or 
                          ($data.To -like "*test*") -or 
                          ($data.To -eq "") -or 
                          ($data.To -is [array])
                if ($isTest) {
                    $dest = Join-Path $archiveDir $f.Name
                    Move-Item -Path $f.FullName -Destination $dest -Force
                    Write-Host "  [ARCHIVED] 已归档测试草稿: $($f.Name)" -ForegroundColor DarkGray
                    $archivedCount++
                }
            } catch {}
        }
        Write-Host ""
        Write-Host "[CLEAN COMPLETE] 成功归档 $archivedCount 封测试草稿至: $archiveDir (未物理删除，安全可回溯)" -ForegroundColor Green
        Write-Host ""
    }

    "send" {
        if (-not $target) {
            Write-Host "[ERROR] 请指定要发送的草稿序号！用法: .\mail.ps1 draft send <序号> --via $account --confirm" -ForegroundColor Red
            exit 1
        }
        $f = Resolve-DraftFile -InputTarget $target
        if (-not $f) {
            Write-Host "[ERROR] 未找到序号对应的草稿: '$target'" -ForegroundColor Red
            exit 1
        }
        $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        
        Write-Host ""
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host " [CONFIRM SEND] 准备外发草稿: $($f.Name)" -ForegroundColor White
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "  通道:   $account 邮箱" -ForegroundColor Cyan
        Write-Host "  收件人: $($data.To) $(if ($data.Name) { '(' + $data.Name + ')' })" -ForegroundColor White
        Write-Host "  主题:   $($data.Subject)" -ForegroundColor Cyan
        if ($data.Attachments -and @($data.Attachments).Count -gt 0) {
            Write-Host "  附件:   $(@($data.Attachments) -join '; ')" -ForegroundColor Yellow
        }
        Write-Host "=================================================================" -ForegroundColor Cyan
        
        if (-not $confirm) {
            Write-Host ""
            Write-Host "⚠️ 安全拦截：外发邮件必须显式二次确认！" -ForegroundColor Yellow
            Write-Host "请追加 --confirm 参数执行正式外发：" -ForegroundColor White
            Write-Host "  .\mail.ps1 draft send $target --via $account --confirm" -ForegroundColor Green
            Write-Host ""
            exit 0
        }

        # 调用底层发信
        Write-Host ""
        Write-Host "[SENDING] 正在通过 $account 发送邮件..." -ForegroundColor Cyan
        $sendArgs = @("-Account", $account, "send", "--to", $data.To, "--subject", $data.Subject, "--body", $data.Body, "--no-sig")
        if ($data.Attachments -and @($data.Attachments).Count -gt 0) {
            $sendArgs += @("--attach", (@($data.Attachments) -join ","))
        }
        & powershell -ExecutionPolicy Bypass -File $script:ENGINE @sendArgs

        # 归档已发草稿
        $sentDir = Join-Path $draftsDir "sent"
        if (-not (Test-Path $sentDir)) { New-Item -ItemType Directory -Path $sentDir -Force | Out-Null }
        Move-Item -Path $f.FullName -Destination (Join-Path $sentDir $f.Name) -Force
        Write-Host "[ARCHIVED] 草稿已移入已发送归档目录: $sentDir" -ForegroundColor DarkGray

        # 同步更新 personal/tracking.csv 为 sent 状态
        $trackingHelper = Join-Path $script:SERVICE_DIR "..\套磁信\core\engine	racking-helper.ps1"
        if (Test-Path $trackingHelper) {
            . $trackingHelper
            Write-TrackingRecord -Recipient $data.To -Name $data.Name -Org $data.Org -Subject $data.Subject -Template $data.Template -Status "sent" -SentVia $account
            Write-Host "[TRACKING] 已同步更新 tracking.csv 状态为 'sent'" -ForegroundColor Green
        }
    }
}
