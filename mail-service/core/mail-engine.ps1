<#
.SYNOPSIS
  统一邮件服务核心引擎 (Unified Mail Service Engine)
.DESCRIPTION
  为高校校园邮箱 (Edu)、QQ 邮箱、网易 163 邮箱、Cloudflare 临时邮箱提供统一的驱动调度与严格隔离处理。
  
  核心隔离机制：
  1. 运行时环境隔离：每次调用前清理进程环境变量，杜绝各邮箱通道凭证串号。
  2. 协议与驱动隔离：标准邮箱路由至 Node.js Bundle (IMAP/SMTP)，临时邮箱路由至 REST API Client。
  3. 资产与数据隔离：各邮箱独立加载签名 (signature.html)、通讯录 (contacts.json)、独立下载目录 (downloads/)、独立审计日志 (mail.log)。
  4. 安全红线隔离：全域物理阻断任何邮件删除指令。

.PARAMETER Account
  目标邮箱配置文件：edu | qq | netease | fmail
.PARAMETER Command
  操作指令：test | check | search | fetch | download | send | mark-read | mark-unread | list-mailboxes | stats | domains | accounts | create
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("edu", "qq", "netease", "campus", "school")]
    [string]$Account,

    [Parameter(Position = 1)]
    [string]$Command = "help",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== 路径定义 ====================

$script:CORE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:SERVICE_ROOT = Split-Path -Parent $script:CORE_DIR
$script:PROFILES_DIR = Join-Path $script:SERVICE_ROOT "profiles"
$script:ACTIVE_PROFILE_DIR = Join-Path $script:PROFILES_DIR $Account

$script:IMAP_SCRIPT = Join-Path $script:CORE_DIR "imap.bundle.js"
$script:SMTP_SCRIPT = Join-Path $script:CORE_DIR "smtp.bundle.js"

# ==================== ⛔ 最高禁令防火墙：物理阻断删除 ====================

$dangerKeywords = @("delete", "remove", "purge", "trash", "expunge", "clean", "destroy")
$allTokens = @($Command) + $RemainingArgs
foreach ($token in $allTokens) {
    if ($null -ne $token) {
        $lower = $token.ToLower().TrimStart("-/")
        if ($lower -in $dangerKeywords -or $lower -like "*delete*" -or $lower -like "*purge*") {
            Write-Host ""
            Write-Host "=================================================================" -ForegroundColor Red
            Write-Host "⛔ 触发最高安全禁令：任何情况下严禁通过脚本删除邮件！" -ForegroundColor Red
            Write-Host "系统已物理阻断该操作。如需清理邮件，请由用户本人登录官方网页端手动处理。" -ForegroundColor Yellow
            Write-Host "=================================================================" -ForegroundColor Red
            Write-Host ""
            exit 403
        }
    }
}

# ==================== 检查并读取 Profile 配置 ====================

$profileJsonPath = Join-Path $script:ACTIVE_PROFILE_DIR "profile.json"
if (-not (Test-Path $profileJsonPath)) {
    $samplePath = Join-Path $script:ACTIVE_PROFILE_DIR "profile.sample.json"
    if (Test-Path $samplePath) {
        Copy-Item $samplePath $profileJsonPath
        Write-Host "[INFO] 首次运行：已从 sample 模版自动初始化 $profileJsonPath，请配置真实邮箱与账号。" -ForegroundColor Yellow
    } else {
        Write-Host "[ERROR] 未找到 Profile 配置文件: $profileJsonPath" -ForegroundColor Red
        exit 1
    }
}

$profileConfig = Get-Content $profileJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:DRIVER = $profileConfig.driver
$script:DISPLAY_NAME = $profileConfig.displayName
$script:MAIL_USER = $profileConfig.email

# 隔离资产路径
$script:PROFILE_DOWNLOADS = Join-Path $script:ACTIVE_PROFILE_DIR "downloads"
if (-not (Test-Path $script:PROFILE_DOWNLOADS)) { New-Item -ItemType Directory -Path $script:PROFILE_DOWNLOADS -Force | Out-Null }

$script:PROFILE_LOG = Join-Path $script:ACTIVE_PROFILE_DIR "mail.log"
$script:PROFILE_SIG = Join-Path $script:ACTIVE_PROFILE_DIR "signature.html"
$sampleSig = Join-Path $script:ACTIVE_PROFILE_DIR "signature.sample.html"
if ((-not (Test-Path $script:PROFILE_SIG)) -and (Test-Path $sampleSig)) {
    Copy-Item $sampleSig $script:PROFILE_SIG
}
$script:PROFILE_CONTACTS = Join-Path $script:ACTIVE_PROFILE_DIR "contacts.json"
$script:PROFILE_CRED = Join-Path $script:ACTIVE_PROFILE_DIR ".credential"
$script:PROFILE_ENV = Join-Path $script:ACTIVE_PROFILE_DIR ".env"

# ==================== 隔离日志记录 ====================

function Write-ProfileLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $script:PROFILE_LOG -Value $logLine -Encoding UTF8
    } catch {}
}

# ==================== 严格环境隔离与凭证加载 ====================

function Clear-ProcessMailEnv {
    $mailEnvKeys = @(
        "IMAP_USER", "IMAP_PASS", "IMAP_HOST", "IMAP_PORT",
        "SMTP_HOST", "SMTP_PORT",
        "NETEASE_EMAIL_USER", "NETEASE_EMAIL_PASS",
        "QQ_EMAIL_USER", "QQ_EMAIL_PASS"
    )
    foreach ($key in $mailEnvKeys) {
        [Environment]::SetEnvironmentVariable($key, $null, "Process")
    }
}

function Load-ProfileCredentials {
    $creds = @{ Pass = ""; Source = "none" }

    # 1. DPAPI 加密凭据优先
    if (Test-Path $script:PROFILE_CRED) {
        try {
            $json = Get-Content $script:PROFILE_CRED -Raw -Encoding UTF8 | ConvertFrom-Json
            $sec = $json.Pass | ConvertTo-SecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            if ($plain) {
                $creds.Pass = $plain
                $creds.Source = "dpapi"
                return $creds
            }
        } catch {}
    }

    # 2. 本地独立 .env 文件
    if (Test-Path $script:PROFILE_ENV) {
        $envKey = $profileConfig.envPassKey
        foreach ($line in (Get-Content $script:PROFILE_ENV)) {
            if ($envKey -and $line -match "^\s*$envKey\s*=\s*(.+)$") {
                $creds.Pass = $matches[1].Trim().Trim('"').Trim("'")
                $creds.Source = "profile-.env"
                return $creds
            }
            if ($line -match '^\s*(?:PASS|PASSWORD|AUTH_CODE)\s*=\s*(.+)$') {
                $creds.Pass = $matches[1].Trim().Trim('"').Trim("'")
                $creds.Source = "profile-.env"
                return $creds
            }
        }
    }

    # 3. 系统环境变量兜底（仅在完全匹配时使用）
    $envPassKey = $profileConfig.envPassKey
    if ($envPassKey -and (Test-Path "Env:$envPassKey")) {
        $creds.Pass = (Get-Item "Env:$envPassKey").Value
        $creds.Source = "system-env"
        return $creds
    }

    return $creds
}

function Apply-ProfileEnv {
    param([hashtable]$Creds)
    # 先做全域清理，确保无前置残留
    Clear-ProcessMailEnv

    # 注入当前 Profile 专属环境变量（同时提供兼容键，满足共享 bundle 依赖）
    if ($profileConfig.envUserKey -and $script:MAIL_USER) {
        [Environment]::SetEnvironmentVariable($profileConfig.envUserKey, $script:MAIL_USER, "Process")
    }
    if ($profileConfig.envPassKey -and $Creds.Pass) {
        [Environment]::SetEnvironmentVariable($profileConfig.envPassKey, $Creds.Pass, "Process")
    }
    # 注入通用桥接变量（确保共享 bundle.js 无论读取哪个变量均能获取当前 profile 凭据）
    [Environment]::SetEnvironmentVariable("NETEASE_EMAIL_USER", $script:MAIL_USER, "Process")
    [Environment]::SetEnvironmentVariable("NETEASE_EMAIL_PASS", $Creds.Pass, "Process")
    [Environment]::SetEnvironmentVariable("QQ_EMAIL_USER", $script:MAIL_USER, "Process")
    [Environment]::SetEnvironmentVariable("QQ_EMAIL_PASS", $Creds.Pass, "Process")

    if ($profileConfig.imapHost) {
        [Environment]::SetEnvironmentVariable("IMAP_HOST", $profileConfig.imapHost, "Process")
    }
    if ($profileConfig.imapPort) {
        [Environment]::SetEnvironmentVariable("IMAP_PORT", [string]$profileConfig.imapPort, "Process")
    }
    if ($profileConfig.smtpHost) {
        [Environment]::SetEnvironmentVariable("SMTP_HOST", $profileConfig.smtpHost, "Process")
    }
    if ($profileConfig.smtpPort) {
        [Environment]::SetEnvironmentVariable("SMTP_PORT", [string]$profileConfig.smtpPort, "Process")
    }
}

# ==================== 附件自动安全规整 ====================

function Resolve-AttachmentPath {
    param([string]$Path)
    if (-not $Path) { return $null }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    }

    if (-not (Test-Path $Path)) {
        Write-Host "[WARN] 附件文件不存在: $Path" -ForegroundColor Yellow
        return $Path
    }

    # 检查常见白名单目录
    $allowedDirs = @(
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Documents",
        $script:SERVICE_ROOT
    )
    foreach ($dir in $allowedDirs) {
        if ($Path.StartsWith($dir, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Path
        }
    }

    # 自动安全复制到当前 Profile 隔离的 downloads 或用户 Downloads
    $filename = [System.IO.Path]::GetFileName($Path)
    $dest = Join-Path "$env:USERPROFILE\Downloads" $filename
    Copy-Item $Path $dest -Force
    Write-Host "[ATTACH] 附件已自动规整至白名单目录: $dest" -ForegroundColor DarkGray
    return $dest
}

# ==================== 联系人别名解析（Profile 专属） ====================

function Resolve-Recipient {
    param([string]$InputTarget)
    if (-not $InputTarget) { return $InputTarget }

    if (Test-Path $script:PROFILE_CONTACTS) {
        try {
            $contacts = Get-Content $script:PROFILE_CONTACTS -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($contacts -is [System.Array]) {
                foreach ($c in $contacts) {
                    if ($c.alias -and [string]$c.alias -eq $InputTarget) {
                        Write-Host "[CONTACT] 解析联系人别名 '$InputTarget' → $($c.email)" -ForegroundColor DarkGray
                        return $c.email
                    }
                    if ($c.name -and [string]$c.name -eq $InputTarget) {
                        Write-Host "[CONTACT] 解析联系人姓名 '$InputTarget' → $($c.email)" -ForegroundColor DarkGray
                        return $c.email
                    }
                }
            } elseif ($contacts -is [System.Collections.IDictionary]) {
                if ($contacts.Contains($InputTarget)) {
                    Write-Host "[CONTACT] 解析联系人别名 '$InputTarget' → $($contacts[$InputTarget])" -ForegroundColor DarkGray
                    return $contacts[$InputTarget]
                }
            } elseif ($contacts.PSObject -and $contacts.PSObject.Properties[$InputTarget]) {
                Write-Host "[CONTACT] 解析联系人别名 '$InputTarget' → $($contacts.$InputTarget)" -ForegroundColor DarkGray
                return $contacts.$InputTarget
            }
        } catch {}
    }
    return $InputTarget
}

# ==================== 网络重试封装 ====================

function Invoke-WithRetry {
    param([scriptblock]$ScriptBlock, [int]$MaxAttempts = 3, [int[]]$Delays = @(2, 4, 8))
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $output = & $ScriptBlock 2>&1
        $success = ($output -match '"success":\s*true') -or ($output -notmatch '"success":\s*false' -and $LASTEXITCODE -eq 0)
        if ($success) { return $output }
        if ($attempt -lt $MaxAttempts) {
            $delay = $Delays[$attempt - 1]
            Write-Host "[RETRY] 操作失败，等待 ${delay}s 后第 $($attempt + 1) 次重试..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
        }
    }
    return $output
}

# ==================== MIME 编码解码 ====================

function Decode-MimeEncodedWord {
    param([string]$Text)
    if ($Text -notmatch '=\?') { return $Text }

    $result = $Text
    $pattern = '=\?([^?]+)\?([BbQq])\?([^?]+)\?='
    $mimeMatches = [regex]::Matches($Text, $pattern)

    foreach ($match in $mimeMatches) {
        $charset = $match.Groups[1].Value
        $encoding = $match.Groups[2].Value.ToUpper()
        $encoded = $match.Groups[3].Value

        try {
            if ($encoding -eq 'B') {
                $bytes = [Convert]::FromBase64String($encoded)
                $decoded = [System.Text.Encoding]::GetEncoding($charset).GetString($bytes)
            } else {
                $encoded = $encoded -replace '_', ' '
                $bytes = [System.Collections.Generic.List[byte]]::new()
                for ($j = 0; $j -lt $encoded.Length; $j++) {
                    if ($encoded[$j] -eq '=' -and $j + 2 -lt $encoded.Length) {
                        $hex = $encoded.Substring($j + 1, 2)
                        $bytes.Add([Convert]::ToByte($hex, 16))
                        $j += 2
                    } else {
                        $bytes.Add([byte][char]$encoded[$j])
                    }
                }
                $decoded = [System.Text.Encoding]::GetEncoding($charset).GetString($bytes.ToArray())
            }
            $result = $result.Replace($match.Value, $decoded)
        } catch {}
    }
    return $result
}

# ==================== 智能搜索（兼容 GB2312/GBK 编码主题） ====================

function Invoke-SmartSearch {
    param(
        [string]$SubjectKeyword = "",
        [string]$FromKeyword = "",
        [string]$Recent = "",
        [string]$Mailbox = "INBOX",
        [int]$Limit = 20
    )

    # 第一步：IMAP 原生搜索
    $searchArgs = @("search")
    if ($SubjectKeyword) { $searchArgs += @("--subject", $SubjectKeyword) }
    if ($FromKeyword) { $searchArgs += @("--from", $FromKeyword) }
    if ($Recent) { $searchArgs += @("--recent", $Recent) }
    if ($Mailbox -ne "INBOX") { $searchArgs += @("--mailbox", $Mailbox) }
    $searchArgs += @("--limit", $Limit)

    $rawResult = & node $script:IMAP_SCRIPT @searchArgs 2>$null | Out-String
    $results = $rawResult | ConvertFrom-Json -ErrorAction SilentlyContinue

    if ($results -and @($results).Count -gt 0) {
        return $results
    }

    # 第二步：原生搜索无结果，拉一批邮件本地解码过滤
    Write-Host "[SEARCH] IMAP 原生搜索无结果，切换本地解码搜索..." -ForegroundColor Yellow

    $checkArgs = @("check", "--limit", [Math]::Max($Limit * 10, 100))
    if ($Recent) { $checkArgs += @("--recent", $Recent) }
    if ($Mailbox -ne "INBOX") { $checkArgs += @("--mailbox", $Mailbox) }

    $allOutput = & node $script:IMAP_SCRIPT @checkArgs 2>$null | Out-String
    $allMails = $allOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

    if (-not $allMails -or @($allMails).Count -eq 0) {
        return @()
    }

    $filtered = @()
    foreach ($mail in $allMails) {
        $decodedSubject = Decode-MimeEncodedWord $mail.subject
        $decodedFrom = Decode-MimeEncodedWord $mail.from

        $matchSubject = (-not $SubjectKeyword) -or ($decodedSubject -like "*$SubjectKeyword*")
        $matchFrom = (-not $FromKeyword) -or ($decodedFrom -like "*$FromKeyword*")

        if ($matchSubject -and $matchFrom) {
            $mail.subject = $decodedSubject
            $mail.from = $decodedFrom
            $filtered += $mail
            if (@($filtered).Count -ge $Limit) { break }
        }
    }

    return $filtered
}

# ==================== 显示帮助 ====================

function Show-EngineHelp {
    Write-Host ""
    Write-Host "  Unified Mail Engine — [$($script:DISPLAY_NAME)]" -ForegroundColor Cyan
    Write-Host "  Profile: $($script:ACTIVE_PROFILE_DIR)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    .\mail-engine.ps1 -Account <edu|qq|netease> <command> [options]"
    Write-Host ""
    Write-Host "  标准邮箱命令 (IMAP / SMTP):" -ForegroundColor White
    Write-Host "    test                  测试 SMTP 和 IMAP 连接"
    Write-Host "    check                 查看收件箱（最新邮件，支持 --limit <N>）"
    Write-Host "    search                搜索邮件（--query <关键词> --from <发件人> --subject <主题>）"
    Write-Host "    fetch <UID>           查看指定邮件全文详情"
    Write-Host "    download <UID>        下载指定邮件的附件（保存至 profile 隔离目录）"
    Write-Host "    send                  发送邮件（--to --subject --body --attach --html --no-sig --draft --schedule）"
    Write-Host "    mark-read <UID>       标记为已读"
    Write-Host "    mark-unread <UID>     标记为未读"
    Write-Host "    list-mailboxes        列出所有邮件文件夹"
    Write-Host "    stats                 查看文件夹统计信息"
    Write-Host ""
}

# ==================== 主分发逻辑 ====================

if ($Command -in @("help", "-h", "--help", "")) {
    Show-EngineHelp
    exit 0
}

# -------------------------------------------------------------
# 分支 2：Bundle 驱动 (Edu / QQ / NetEase 163 标准 IMAP/SMTP)
# -------------------------------------------------------------

# 加载凭据
$creds = Load-ProfileCredentials
if (-not $creds.Pass) {
    Write-Host "[ERROR] 未找到 $($script:DISPLAY_NAME) 的授权码凭证！" -ForegroundColor Red
    Write-Host "  请检查 profiles\$Account\.env 或运行 .\mail-service\core\setup-credential.ps1 -Profile $Account" -ForegroundColor Yellow
    exit 1
}

try {
    # 严格环境注入
    Apply-ProfileEnv -Creds $creds

    switch ($Command.ToLower()) {
        "test" {
            Write-Host "=== $($script:DISPLAY_NAME) 连接测试 ($($script:MAIL_USER)) ===" -ForegroundColor Cyan
            Write-Host "凭证来源: $($creds.Source)" -ForegroundColor DarkGray
            Write-Host ""

            Write-Host "[SMTP] 测试 SMTP 发信连接..." -NoNewline
            $smtpTest = node $script:SMTP_SCRIPT test 2>&1
            if ($smtpTest -match '"success":\s*true') {
                Write-Host " [成功 ✓]" -ForegroundColor Green
            } else {
                Write-Host " [失败 ✗]" -ForegroundColor Red
                Write-Host $smtpTest -ForegroundColor DarkGray
            }

            Write-Host "[IMAP] 测试 IMAP 收信连接..." -NoNewline
            $imapTest = node $script:IMAP_SCRIPT check --limit 1 2>&1
            if ($imapTest -notmatch '"success":\s*false') {
                Write-Host " [成功 ✓]" -ForegroundColor Green
            } else {
                Write-Host " [失败 ✗]" -ForegroundColor Red
                Write-Host $imapTest -ForegroundColor DarkGray
            }
        }

        "check" {
            $nodeArgs = @("check") + $RemainingArgs
            node $script:IMAP_SCRIPT @nodeArgs
        }

        "search" {
            # 智能搜索：兼容 GB2312/GBK 编码主题
            $subj = ""; $from = ""; $recent = ""; $mbox = "INBOX"; $lim = 20
            $i = 0
            while ($i -lt $RemainingArgs.Count) {
                switch ($RemainingArgs[$i]) {
                    "--subject" { $subj = $RemainingArgs[++$i] }
                    "--from" { $from = $RemainingArgs[++$i] }
                    "--recent" { $recent = $RemainingArgs[++$i] }
                    "--mailbox" { $mbox = $RemainingArgs[++$i] }
                    "--limit" { $lim = [int]$RemainingArgs[++$i] }
                }
                $i++
            }

            $results = Invoke-SmartSearch -SubjectKeyword $subj -FromKeyword $from -Recent $recent -Mailbox $mbox -Limit $lim
            if ($results -and @($results).Count -gt 0) {
                $results | ConvertTo-Json -Depth 10
                Write-ProfileLog -Message "search subject=$subj from=$from count=$(@($results).Count)"
            } else {
                Write-Host "[SEARCH] 未找到匹配邮件。" -ForegroundColor Yellow
                Write-ProfileLog -Message "search subject=$subj from=$from count=0"
            }
        }

        "fetch" {
            $nodeArgs = @("fetch") + $RemainingArgs
            node $script:IMAP_SCRIPT @nodeArgs
        }

        "download" {
            # 默认下载至 profile 专属 downloads 目录
            $hasOutput = $false
            for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
                if ($RemainingArgs[$i] -in @("--output", "-o")) { $hasOutput = $true; break }
            }
            $nodeArgs = @("download") + $RemainingArgs
            if (-not $hasOutput) {
                $nodeArgs += @("--output", $script:PROFILE_DOWNLOADS)
            }
            node $script:IMAP_SCRIPT @nodeArgs
        }

        "mark-read" {
            $nodeArgs = @("mark-read") + $RemainingArgs
            node $script:IMAP_SCRIPT @nodeArgs
        }

        "mark-unread" {
            $nodeArgs = @("mark-unread") + $RemainingArgs
            node $script:IMAP_SCRIPT @nodeArgs
        }

        "list-mailboxes" {
            node $script:IMAP_SCRIPT list-mailboxes
        }

        "stats" {
            Write-Host "=== $($script:DISPLAY_NAME) 文件夹统计 ===" -ForegroundColor Cyan
            node $script:IMAP_SCRIPT list-mailboxes
        }

        "list-drafts" {
            $draftsDir = Join-Path $script:ACTIVE_PROFILE_DIR "drafts"
            Write-Host "=== $($script:DISPLAY_NAME) 本地草稿箱列表 ===" -ForegroundColor Cyan
            if (Test-Path $draftsDir) {
                $files = @(Get-ChildItem -Path $draftsDir -Filter "*.json" | Sort-Object LastWriteTime -Descending)
                if ($files.Count -eq 0) {
                    Write-Host "  暂无待发草稿。" -ForegroundColor DarkGray
                } else {
                    $idx = 1
                    foreach ($f in $files) {
                        try {
                            $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                            $recip = if ($data.Name) { "$($data.Name) <$($data.To)>" } else { "$($data.To)" }
                            Write-Host "  [$idx] $($f.Name)" -ForegroundColor Yellow
                            Write-Host "      收件人: $recip" -ForegroundColor White
                            Write-Host "      主  题: $($data.Subject)" -ForegroundColor Cyan
                            Write-Host "      时  间: $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor DarkGray
                            $idx++
                        } catch {}
                    }
                }
            } else {
                Write-Host "  草稿目录尚未创建。" -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host "  发送命令: .\mail.ps1 send-draft <序号> --via $Account --confirm" -ForegroundColor DarkCyan
        }

        "send-draft" {
            $target = ""
            $confirm = $false
            $i = 0
            while ($i -lt $RemainingArgs.Count) {
                if ($RemainingArgs[$i] -in @("--confirm", "-confirm")) {
                    $confirm = $true
                } elseif (-not $target -and -not $RemainingArgs[$i].StartsWith("-")) {
                    $target = $RemainingArgs[$i]
                }
                $i++
            }

            $draftsDir = Join-Path $script:ACTIVE_PROFILE_DIR "drafts"
            if (-not $target) {
                Write-Host "[ERROR] 请指定要发送的草稿序号或文件名！" -ForegroundColor Red
                Write-Host "用法示例:" -ForegroundColor Yellow
                Write-Host "  .\mail.ps1 list-drafts --via $Account"
                Write-Host "  .\mail.ps1 send-draft 1 --via $Account --confirm"
                exit 1
            }

            $selectedFile = $null
            $files = @(Get-ChildItem -Path $draftsDir -Filter "*.json" | Sort-Object LastWriteTime -Descending)
            if ($target -match '^\d+$') {
                $num = [int]$target
                if ($num -ge 1 -and $num -le $files.Count) {
                    $selectedFile = $files[$num - 1].FullName
                } else {
                    Write-Host "[ERROR] 草稿序号无效: $target (当前有效范围: 1-$($files.Count))" -ForegroundColor Red
                    exit 1
                }
            } elseif (Test-Path $target) {
                $selectedFile = (Resolve-Path $target).Path
            } else {
                $cand = Join-Path $draftsDir $target
                if (Test-Path $cand) { $selectedFile = (Resolve-Path $cand).Path }
                elseif (Test-Path "$cand.json") { $selectedFile = (Resolve-Path "$cand.json").Path }
            }

            if (-not $selectedFile -or -not (Test-Path $selectedFile)) {
                Write-Host "[ERROR] 未找到草稿文件: $target" -ForegroundColor Red
                exit 1
            }

            $draftData = Get-Content $selectedFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $draftTo = $draftData.To
            $draftSubj = $draftData.Subject
            $draftBody = $draftData.Body
            $draftAttach = $draftData.Attachments

            Write-Host ""
            Write-Host "=================================================================" -ForegroundColor Cyan
            Write-Host " [DRAFT PREVIEW] 待发送草稿确认: $(Split-Path -Leaf $selectedFile)" -ForegroundColor White
            Write-Host "=================================================================" -ForegroundColor Cyan
            Write-Host "  发信邮箱: $($script:DISPLAY_NAME) ($($script:MAIL_USER))" -ForegroundColor White
            Write-Host "  收件人:   $draftTo $(if ($draftData.Name) { '(' + $draftData.Name + ')' })" -ForegroundColor White
            Write-Host "  主题:     $draftSubj" -ForegroundColor Cyan
            if ($draftAttach -and @($draftAttach).Count -gt 0) {
                Write-Host "  挂载附件: $(@($draftAttach) -join '; ')" -ForegroundColor DarkGray
            }
            Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "【正文预览】:" -ForegroundColor Yellow
            $draftBody.Split("`n") | Select-Object -First 6 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            if ($draftBody.Split("`n").Count -gt 6) { Write-Host "  ..." -ForegroundColor DarkGray }
            Write-Host "=================================================================" -ForegroundColor Cyan

            if (-not $confirm) {
                Write-Host ""
                Write-Host "⚠️ 安全拦截：外发邮件必须显式二次确认！" -ForegroundColor Yellow
                Write-Host "若确认核对无误并正式发出，请加上 --confirm 参数执行：" -ForegroundColor White
                Write-Host "  .\mail.ps1 send-draft $target --via $Account --confirm" -ForegroundColor Green
                Write-Host ""
                exit 0
            }

            # 执行外发
            Write-Host ""
            Write-Host "[SENDING] 正在通过 $($script:DISPLAY_NAME) 发信..." -ForegroundColor Cyan
            $sendArgs = @("-Account", $Account, "send", "--to", $draftTo, "--subject", $draftSubj, "--body", $draftBody, "--no-sig")
            if ($draftAttach -and @($draftAttach).Count -gt 0) {
                $sendArgs += @("--attach", (@($draftAttach) -join ","))
            }
            & powershell -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Definition @sendArgs

            # 发送成功后归档草稿至 sent 目录（防误重发，保留审计，严禁删除）
            $sentArchiveDir = Join-Path $draftsDir "sent"
            if (-not (Test-Path $sentArchiveDir)) { New-Item -ItemType Directory -Path $sentArchiveDir -Force | Out-Null }
            $archivePath = Join-Path $sentArchiveDir (Split-Path -Leaf $selectedFile)
            Move-Item -Path $selectedFile -Destination $archivePath -Force
            Write-Host "[ARCHIVE] 草稿已安全归档至已发目录: $archivePath" -ForegroundColor DarkGray
        }

        "send" {
            $to = ""; $subject = ""; $body = ""; $attach = ""; $html = $false; $noSig = $false
            $draft = $false; $schedule = ""

            $i = 0
            while ($i -lt $RemainingArgs.Count) {
                switch ($RemainingArgs[$i]) {
                    "--to" { $to = $RemainingArgs[++$i] }
                    "--subject" { $subject = $RemainingArgs[++$i] }
                    "--body" { $body = $RemainingArgs[++$i] }
                    "--attach" { $attach = $RemainingArgs[++$i] }
                    "--html" { $html = $true }
                    "--no-sig" { $noSig = $true }
                    "--draft" { $draft = $true }
                    "--schedule" { $schedule = $RemainingArgs[++$i] }
                }
                $i++
            }

            if (-not $to -or -not $subject) {
                Write-Host "[ERROR] 发信必须提供 --to 和 --subject 参数！" -ForegroundColor Red
                exit 1
            }

            # 别名解析（如果是通讯录里的名字）
            $to = Resolve-Recipient -InputTarget $to

            # 自动注入当前邮箱的专属签名（若存在且未指定 --no-sig）
            if (-not $noSig -and (Test-Path $script:PROFILE_SIG)) {
                $sigContent = Get-Content $script:PROFILE_SIG -Raw -Encoding UTF8
                $body = "$body<br><br>$sigContent"
                $html = $true
            }

            # 附件规整
            if ($attach) {
                $attach = Resolve-AttachmentPath -Path $attach
            }

            # 草稿处理
            if ($draft) {
                $draftsDir = Join-Path $script:ACTIVE_PROFILE_DIR "drafts"
                if (-not (Test-Path $draftsDir)) { New-Item -ItemType Directory -Path $draftsDir -Force | Out-Null }
                $draftFile = Join-Path $draftsDir "draft_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                @{ Account = $Account; To = $to; Subject = $subject; Body = $body; Attach = $attach } |
                    ConvertTo-Json | Set-Content $draftFile -Encoding UTF8
                Write-Host "[DRAFT] 已保存本地草稿: $draftFile" -ForegroundColor Green

                # 同步推送到远端邮箱的云端草稿箱（方便在 Web 网页版或客户端直接查看/外发）
                Write-Host "[IMAP DRAFT] 正在同步推送至 $($script:DISPLAY_NAME) 云端草稿箱..." -ForegroundColor Cyan
                $draftArgs = @("save-draft", "--to", $to, "--subject", $subject, "--body", $body)
                if ($html) { $draftArgs += "--html" }
                if ($attach) { $draftArgs += @("--attach", $attach) }
                $imapDraftOutput = & node $script:IMAP_SCRIPT @draftArgs 2>&1
                if ($imapDraftOutput -match '"success":\s*true') {
                    Write-Host "  → 云端草稿箱同步成功 ✓ (您可在网页邮箱或客户端草稿箱中直接看到并随时编辑发送)" -ForegroundColor Green
                } else {
                    Write-Host "  → 云端草稿箱同步跳过/提示: $imapDraftOutput" -ForegroundColor DarkGray
                }
                exit 0
            }

            # 定时发送：创建 Windows 任务计划一次性任务
            if ($schedule) {
                $taskName = "mail_send_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                $enginePath = $MyInvocation.MyCommand.Definition

                # 构建定时执行的参数（去掉 --schedule）
                $taskArgs = @("-Account", $Account, "send", "--to", $to, "--subject", $subject, "--body", $body)
                if ($html) { $taskArgs += "--html" }
                if ($attach) { $taskArgs += @("--attach", $attach) }
                if ($noSig) { $taskArgs += "--no-sig" }

                # 写入临时配置文件避免参数转义问题
                $taskConfig = @{
                    engine = $enginePath
                    args = $taskArgs
                    account = $Account
                    to = $to
                    subject = $subject
                }
                $taskConfigFile = Join-Path $script:ACTIVE_PROFILE_DIR "scheduled_$taskName.json"
                $taskConfig | ConvertTo-Json -Depth 5 | Set-Content $taskConfigFile -Encoding UTF8

                # 创建 PowerShell 启动脚本
                $launcherScript = @"
`$config = Get-Content '$taskConfigFile' -Raw | ConvertFrom-Json
& powershell -ExecutionPolicy Bypass -File `$config.engine @($config.args)
"@
                $launcherPath = Join-Path $script:ACTIVE_PROFILE_DIR "run_$taskName.ps1"
                Set-Content -Path $launcherPath -Value $launcherScript -Encoding UTF8

                # 解析时间并创建任务计划
                try {
                    $scheduleTime = [DateTime]::Parse($schedule)
                    $now = Get-Date
                    if ($scheduleTime -le $now) {
                        Write-Host "[ERROR] 定时发送时间必须在未来: $schedule" -ForegroundColor Red
                        exit 1
                    }

                    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPath`""
                    $trigger = New-ScheduledTaskTrigger -Once -At $scheduleTime
                    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DeleteExpiredTaskAfter 1:00:00

                    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

                    Write-Host "[SCHEDULE] 定时发送已创建：" -ForegroundColor Green
                    Write-Host "  任务名称: $taskName" -ForegroundColor White
                    Write-Host "  发送时间: $scheduleTime (Beijing time)" -ForegroundColor White
                    Write-Host "  收件人:   $to" -ForegroundColor White
                    Write-Host "  主题:     $subject" -ForegroundColor White
                    Write-Host "  启动脚本: $launcherPath" -ForegroundColor DarkGray
                    Write-ProfileLog -Message "Scheduled send to $to at $scheduleTime, task: $taskName" -Level "INFO"
                    exit 0
                } catch {
                    Write-Host "[ERROR] 定时发送创建失败: $_" -ForegroundColor Red
                    Write-ProfileLog -Message "Failed to create schedule: $_" -Level "ERROR"
                    exit 1
                }
            }

            # 构建发信参数
            $nodeArgs = @("send", "--to", $to, "--subject", $subject, "--body", $body)
            if ($html) { $nodeArgs += "--html" }
            if ($attach) { $nodeArgs += @("--attach", $attach) }

            Write-Host "[SEND] 正在通过 $($script:DISPLAY_NAME) 发送到: $to ..." -ForegroundColor Cyan
            $output = Invoke-WithRetry -ScriptBlock { node $script:SMTP_SCRIPT @nodeArgs }
            $success = $output -match '"success":\s*true'

            if ($success) {
                Write-Host "  → 发送成功 ✓" -ForegroundColor Green
                Write-ProfileLog -Message "Sent mail to $to, subject: $subject" -Level "INFO"
            } else {
                Write-Host "  → 发送失败 ✗" -ForegroundColor Red
                Write-Host $output -ForegroundColor DarkGray
                Write-ProfileLog -Message "Failed sending mail to ${to}: $output" -Level "ERROR"
            }
        }

        default {
            Write-Host "[ERROR] 未知命令: $Command" -ForegroundColor Red
            Show-EngineHelp
            exit 1
        }
    }
} finally {
    # 彻底清理环境变量，杜绝跨会话交叉污染
    Clear-ProcessMailEnv
}
