
param([switch]$Json)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:CORE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:SERVICE_DIR = Split-Path -Parent $script:CORE_DIR
$script:PROJECT_ROOT = Split-Path -Parent $script:SERVICE_DIR

$script:ENGINE = Join-Path $script:CORE_DIR "mail-engine.ps1"
$script:SKILL_DIR = Join-Path $script:PROJECT_ROOT "套磁信"
$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:PROFILE_FILE = Join-Path $script:PERSONAL_DIR "profile.json"

$score = 100
$issues = @()
$channelResults = @{}

if (-not $Json) {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "      Mail-AI & 推免套磁系统全能体检中心 (System Doctor)" -ForegroundColor Cyan
    Write-Host "      时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | 系统: Windows" -ForegroundColor DarkGray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "【1. 邮箱核心通道测试】" -ForegroundColor White
}

foreach ($acc in @("edu", "qq", "netease")) {
    if (-not $Json) { Write-Host "  - 正在检测 $acc 通道 ... " -NoNewline }
    $tRes = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $acc test 2>&1
    $smtpOk = ($tRes -match 'SMTP.*成功')
    $imapOk = ($tRes -match 'IMAP.*成功')
    
    $channelResults[$acc] = @{
        smtp = [bool]$smtpOk
        imap = [bool]$imapOk
        status = if ($smtpOk -and $imapOk) { "ok" } elseif ($smtpOk) { "smtp_only" } else { "failed" }
    }

    if (-not $Json) {
        if ($smtpOk -and $imapOk) {
            Write-Host "[正常 ✓] (SMTP + IMAP 双通)" -ForegroundColor Green
        } elseif ($smtpOk) {
            Write-Host "[部分受限] (仅 SMTP 成功，IMAP 异常)" -ForegroundColor Yellow
            $score -= 10
            $issues += "$acc IMAP 收信异常"
        } else {
            Write-Host "[失败 ✗] 连接未通过" -ForegroundColor Red
            $score -= 20
            $issues += "$acc 邮箱凭据或连接失败"
        }
    } else {
        if (-not ($smtpOk -and $imapOk)) {
            if ($smtpOk) { $score -= 10; $issues += "$acc IMAP 收信异常" }
            else { $score -= 20; $issues += "$acc 邮箱凭据或连接失败" }
        }
    }
}

# Fmail API
if (-not $Json) { Write-Host "  - 正在检测 Fmail (Cloudflare 临时邮箱) ... " -NoNewline }
$fmailScript = Join-Path $script:PROJECT_ROOT "fmail\fmail.ps1"
$fmailStatus = "unavailable"
if (Test-Path $fmailScript) {
    $fRes = & powershell -ExecutionPolicy Bypass -File $fmailScript domains 2>&1
    if ($fRes -match '可用域名列表') {
        $fmailStatus = "ok"
        if (-not $Json) { Write-Host "[正常 ✓] (API 在线可用)" -ForegroundColor Green }
    } else {
        $fmailStatus = "degraded"
        if (-not $Json) { Write-Host "[未就绪] (API 无响应)" -ForegroundColor Yellow }
        $score -= 5
        $issues += "Fmail 临时邮箱未配置或不可用"
    }
} else {
    $fmailStatus = "missing"
    if (-not $Json) { Write-Host "[跳过] (未安装 fmail 模块)" -ForegroundColor DarkGray }
}
$channelResults["fmail"] = @{ status = $fmailStatus }

if (-not $Json) {
    Write-Host ""
    Write-Host "【2. 推免材料库与默认附件体检】" -ForegroundColor White
}

$profileInfo = @{ status = "missing"; name = ""; school = ""; resume_valid = $false; resume_size_mb = 0 }
if (Test-Path $script:PROFILE_FILE) {
    try {
        $profile = Get-Content $script:PROFILE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
        $profileInfo.status = "ok"
        $profileInfo.name = $profile.name
        $profileInfo.school = "$($profile.school) $($profile.college) $($profile.major)"
        if (-not $Json) {
            Write-Host "  - 个人画像 (profile.json): [正常 ✓] (已配置 $($profile.name) - $($profile.school)$($profile.college)$($profile.major))" -ForegroundColor Green
        }
        
        $resPath = $profile.default_attachments.resume
        if ($resPath -and (Test-Path $resPath)) {
            $fObj = Get-Item $resPath
            $fSizeMB = [math]::Round($fObj.Length / 1MB, 2)
            $profileInfo.resume_valid = ($fSizeMB -le 5.0)
            $profileInfo.resume_size_mb = $fSizeMB
            $profileInfo.resume_name = $fObj.Name
            if (-not $Json) {
                if ($fSizeMB -le 5.0) {
                    Write-Host "  - 默认简历材料: [正常 ✓] ($($fObj.Name) | $fSizeMB MB ≤ 5MB)" -ForegroundColor Green
                } else {
                    Write-Host "  - 默认简历材料: [超限 ✗] ($($fObj.Name) | $fSizeMB MB > 5MB 存在拦截风险)" -ForegroundColor Red
                    $score -= 15
                    $issues += "默认简历附件体积超过 5MB"
                }
            } else {
                if ($fSizeMB -gt 5.0) { $score -= 15; $issues += "默认简历附件体积超过 5MB" }
            }
        } else {
            $profileInfo.resume_valid = $false
            if (-not $Json) {
                Write-Host "  - 默认简历材料: [未配置 ✗] profile.json 中 resume 路径无效！" -ForegroundColor Red
                $score -= 10
                $issues += "未绑定有效的默认简历材料"
            } else {
                $score -= 10; $issues += "未绑定有效的默认简历材料"
            }
        }
    } catch {
        $profileInfo.status = "error"
        if (-not $Json) {
            Write-Host "  - 个人画像 (profile.json): [解析失败 ✗] JSON 格式错误" -ForegroundColor Red
            $score -= 10
            $issues += "profile.json 解析失败"
        } else {
            $score -= 10; $issues += "profile.json 解析失败"
        }
    }
} else {
    $profileInfo.status = "missing"
    if (-not $Json) {
        Write-Host "  - 个人画像 (profile.json): [未配置（开源样板模式）]" -ForegroundColor Yellow
    }
}

if (-not $Json) {
    Write-Host ""
    Write-Host "【3. 追踪数据与草稿箱状态】" -ForegroundColor White
}

$eduDrafts = Join-Path $script:SERVICE_DIR "profiles\edu\drafts"
if (-not (Test-Path $eduDrafts)) { $eduDrafts = Join-Path $script:SERVICE_DIR "profiles\campus\drafts" }
$draftCount = if (Test-Path $eduDrafts) { @(Get-ChildItem $eduDrafts -Filter "*.json").Count } else { 0 }
if (-not $Json) { Write-Host "  - 校园邮箱本地草稿数: $draftCount 封待发草稿" -ForegroundColor Cyan }

$trackingFile = Join-Path $script:PERSONAL_DIR "tracking.csv"
$trackingCount = 0
if (Test-Path $trackingFile) {
    try {
        $tracks = @(Import-Csv $trackingFile)
        $trackingCount = $tracks.Count
        if (-not $Json) { Write-Host "  - 投递追踪日志 (tracking.csv): [正常 ✓] (记录数: $($tracks.Count))" -ForegroundColor Green }
    } catch {
        if (-not $Json) { Write-Host "  - 投递追踪日志: [读取异常]" -ForegroundColor Yellow }
    }
} else {
    if (-not $Json) { Write-Host "  - 投递追踪日志: [未初始化 (首次使用自动建立)]" -ForegroundColor DarkGray }
}

if (-not $Json) {
    Write-Host ""
    Write-Host "【4. 垃圾箱与误拦截风险扫描】" -ForegroundColor White
}

$spamCount = 0
$adCount = 0
$scanRes = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account edu list-mailboxes 2>&1
if ($scanRes -match '垃圾邮件|Junk|Spam') {
    $sRes = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account edu check --folder "垃圾邮件" --limit 1 2>&1
    if ($sRes -match '\[\s*\]') { $spamCount = 0 }
}
if ($scanRes -match '广告邮件|Advertisement') {
    $aRes = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account edu check --folder "广告邮件" --limit 1 2>&1
    if ($aRes -match '\[\s*\]') { $adCount = 0 }
}

if (-not $Json) {
    if ($spamCount -eq 0 -and $adCount -eq 0) {
        Write-Host "  - 校园邮箱垃圾邮件箱: 为空 | 广告邮件箱: 为空" -ForegroundColor DarkGray
        Write-Host "    ✓ 无误拦截风险" -ForegroundColor Green
    } else {
        Write-Host "  - ⚠️ 垃圾/广告箱中发现 $spamCount 封邮件，建议运行 '.\mail.ps1 scan' 确认是否有推免初审回信！" -ForegroundColor Yellow
        $score -= 5
        $issues += "垃圾/广告邮件箱有未读拦截"
    }

    Write-Host ""
    Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
    $rating = if ($score -ge 95) { "极佳 (EXCELLENT)" } elseif ($score -ge 80) { "良好 (GOOD)" } else { "需关注 (ATTENTION REQUIRED)" }
    $scoreColor = if ($score -ge 90) { "Green" } elseif ($score -ge 75) { "Yellow" } else { "Red" }
    Write-Host " 综合体检得分: $score / 100 — $rating" -ForegroundColor $scoreColor
    if ($issues.Count -gt 0) {
        Write-Host " 待处理优化项:" -ForegroundColor Yellow
        foreach ($iss in $issues) { Write-Host "   • $iss" -ForegroundColor Yellow }
    }
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
} else {
    $resultObj = @{
        status = if ($score -ge 80) { "healthy" } else { "warning" }
        score = [math]::Max(0, $score)
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        channels = $channelResults
        profile = $profileInfo
        drafts = @{ edu_count = $draftCount }
        tracking = @{ count = $trackingCount }
        spam_scan = @{ spam_count = $spamCount; ad_count = $adCount; clean = ($spamCount -eq 0 -and $adCount -eq 0) }
        issues = $issues
    }
    $resultObj | ConvertTo-Json -Depth 5 -Compress:$false
}
