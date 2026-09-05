<#
.SYNOPSIS
  通用学术推免套磁信智能批量发送引擎 (Universal Outreach Batch Engine)
.DESCRIPTION
  分层架构：
    1. 通用底座设计：代码零个人隐私信息硬编码，开箱即用，适合打包分享与复用。
    2. 隐私隔离优先：发信日志、导师联系人、个人画像与附件默认隔离在 personal/ 目录下。
    3. 级联模板与配置：优先加载 personal/profile.json 与 personal/templates/；未特调时平滑回退至 core/。
    4. 附件安全与防封：支持多附件体积预检、14 天查重防手滑拦截、30-60s 随机安全抖动。
    5. 强制通道确认：发信模式强制 --via <edu|qq|netease>，严禁猜测。

  用法：
    # 预览模式 (Dry-Run)
    powershell -ExecutionPolicy Bypass -File .\batch-send.ps1 --csv "..\personal\contacts.csv" --template A --dry-run

    # 正式发送 (挂载附件并指定通道)
    powershell -ExecutionPolicy Bypass -File .\batch-send.ps1 --csv "..\personal\contacts.csv" --template A --attach "简历.pdf,个人陈述.pdf" --via edu
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ENGINE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:CORE_DIR = Split-Path -Parent $script:ENGINE_DIR
$script:SKILL_DIR = Split-Path -Parent $script:CORE_DIR
$script:PROJECT_ROOT = Split-Path -Parent $script:SKILL_DIR

# 路径约定
$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:CORE_TEMPLATES = Join-Path $script:CORE_DIR "templates"
$script:CORE_SCHEMAS = Join-Path $script:CORE_DIR "schemas"
$script:MAIL_ENGINE = Join-Path $script:PROJECT_ROOT "mail-ai\core\mail-engine.ps1"

# ==================== 1. 级联加载个人画像 ====================

$script:Profile = $null
$profileCandidates = @(
    (Join-Path $script:PERSONAL_DIR "profile.json"),
    (Join-Path $script:SKILL_DIR "student_profile.json"),
    (Join-Path $script:CORE_SCHEMAS "student_profile.sample.json")
)

foreach ($cand in $profileCandidates) {
    if (Test-Path $cand) {
        try {
            $raw = Get-Content $cand -Raw -Encoding UTF8
            $script:Profile = $raw | ConvertFrom-Json
            $script:ACTIVE_PROFILE_PATH = $cand
            break
        } catch {}
    }
}

if (-not $script:Profile) {
    Write-Host "[ERROR] 未能加载任何个人画像配置 (profile.json)！" -ForegroundColor Red
    exit 1
}

# 提取变量
$script:MY_NAME = if ($script:Profile.name) { $script:Profile.name } else { "同学" }
$script:MY_NAME_EN = if ($script:Profile.name_en) { $script:Profile.name_en } else { "Applicant" }
$script:MY_SCHOOL = if ($script:Profile.school) { $script:Profile.school } else { "大学" }
$script:MY_SCHOOL_EN = if ($script:Profile.school_en) { $script:Profile.school_en } else { "University" }
$script:MY_COLLEGE = if ($script:Profile.college) { $script:Profile.college } else { "" }
$script:MY_COLLEGE_EN = if ($script:Profile.college_en) { $script:Profile.college_en } else { "" }
$script:MY_MAJOR = if ($script:Profile.major) { $script:Profile.major } else { "专业" }
$script:MY_MAJOR_EN = if ($script:Profile.major_en) { $script:Profile.major_en } else { "Major" }
$script:MY_EMAIL = if ($script:Profile.primary_email) { $script:Profile.primary_email } else { "" }
$script:MY_INTENT = if ($script:Profile.intent) { $script:Profile.intent } else { "申请攻读研究生" }
$script:ADVISOR = if ($script:Profile.research_background.advisor) { $script:Profile.research_background.advisor } else { "指导老师" }
$script:PROJECT_NAME = if ($script:Profile.research_background.project_name) { $script:Profile.research_background.project_name } else { "本科科研课题" }
$script:EXP_SUMMARY = if ($script:Profile.research_background.experience_summary) { $script:Profile.research_background.experience_summary } else { "有一年独立科研经历，能较快融入课题组科研工作" }
$script:EXP_SUMMARY_EN = if ($script:Profile.research_background.experience_summary_en) { $script:Profile.research_background.experience_summary_en } else { "I have independent research experience and can quickly contribute to your group." }

# ==================== 2. 级联模板引擎 (Personal 优先，Core 回退) ====================

function Get-TemplateContent {
    param([string]$Type)
    
    $typeUpper = $Type.ToUpper()
    $templateFile = $null
    
    # 1. 优先从 personal/templates/ 寻找特调模板
    $personalTplDir = Join-Path $script:PERSONAL_DIR "templates"
    if (Test-Path $personalTplDir) {
        $pMatches = Get-ChildItem -Path $personalTplDir | Where-Object { $_.Name -match "^(template_|standard_)?$typeUpper(_|\.|\$)" }
        if ($pMatches.Count -gt 0) { $templateFile = $pMatches[0].FullName }
    }
    
    # 2. 回退到 core/templates/ 寻找通用标准模板
    if (-not $templateFile -and (Test-Path $script:CORE_TEMPLATES)) {
        $cMatches = Get-ChildItem -Path $script:CORE_TEMPLATES | Where-Object { $_.Name -match "^(standard_|template_)?$typeUpper(_|\.|\$)" }
        if ($cMatches.Count -gt 0) { $templateFile = $cMatches[0].FullName }
    }
    
    if ($templateFile -and (Test-Path $templateFile)) {
        $raw = Get-Content $templateFile -Raw -Encoding UTF8
        $subj = ""
        $body = ""
        if ($raw -match "(?ms)SUBJECT:\s*(.*?)\r?\n---BODY---\r?\n(.*)") {
            $subj = $matches[1].Trim()
            $body = $matches[2]
        } else {
            $body = $raw
            $subj = "研究生申请信——$script:MY_SCHOOL$script:MY_MAJOR$script:MY_NAME"
        }
        return @{ Subject = $subj; Body = $body; Source = $templateFile }
    }
    
    # 保底
    return @{
        Subject = "研究生申请信——$script:MY_SCHOOL$script:MY_MAJOR$script:MY_NAME"
        Body = "{{NAME}}{{TITLE}}您好，我是$script:MY_SCHOOL$script:MY_MAJOR专业$script:MY_NAME。对您的{{INTEREST}}研究很感兴趣。附有个人简历供您了解。祝好！"
        Source = "fallback"
    }
}

function Render-MailText {
    param([string]$Text, [hashtable]$Vars)
    $res = $Text
    foreach ($k in $Vars.Keys) {
        $val = if ($Vars[$k]) { [string]$Vars[$k] } else { "" }
        $res = $res.Replace("{{$k}}", $val)
    }
    return $res
}

# ==================== 3. 隐私追踪与防手滑查重 ====================

$script:TRACKING_FILE = Join-Path $script:PERSONAL_DIR "tracking.csv"

function Init-Tracking {
    if (-not (Test-Path $script:PERSONAL_DIR)) {
        New-Item -ItemType Directory -Path $script:PERSONAL_DIR -Force | Out-Null
    }
    if (-not (Test-Path $script:TRACKING_FILE)) {
        "date,sender,recipient,name,org,subject,template,status,sent_via,days_no_reply" | 
            Out-File $script:TRACKING_FILE -Encoding UTF8
    }
}

function Check-RecentSent {
    param([string]$Recipient, [int]$WindowDays = 14)
    if (-not (Test-Path $script:TRACKING_FILE)) { return $null }
    try {
        $records = Import-Csv $script:TRACKING_FILE
        $cutoff = (Get-Date).AddDays(-$WindowDays)
        return $records | Where-Object { 
            $_.recipient -ieq $Recipient -and 
            $_.status -ieq "sent" -and 
            ([datetime]::Parse($_.date) -ge $cutoff) 
        } | Select-Object -Last 1
    } catch {
        return $null
    }
}

function Write-Tracking {
    param([string]$Recipient, [string]$Name, [string]$Org, [string]$Subject, [string]$Template, [string]$Status, [string]$SentVia)
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$date,$script:MY_EMAIL,$Recipient,$Name,$Org,$Subject,$Template,$Status,$SentVia," | 
        Out-File $script:TRACKING_FILE -Append -Encoding UTF8
}

# ==================== 4. 附件安全预检 ====================

function Resolve-Attachments {
    param([string[]]$AttachInputs, [switch]$DefaultAttach)
    
    $resultFiles = @()
    $personalAttDir = Join-Path $script:PERSONAL_DIR "attachments"
    
    if ($DefaultAttach -and $script:Profile.default_attachments) {
        foreach ($prop in @("resume", "personal_statement", "presentation")) {
            $p = $script:Profile.default_attachments.$prop
            if ($p -and (Test-Path $p)) { $resultFiles += (Resolve-Path $p).Path }
        }
    }
    
    foreach ($item in $AttachInputs) {
        if (-not $item) { continue }
        $splits = $item -split ","
        foreach ($f in $splits) {
            $fClean = $f.Trim().Trim('"').Trim("'")
            if (-not $fClean) { continue }
            if (Test-Path $fClean) {
                $resultFiles += (Resolve-Path $fClean).Path
            } else {
                # 尝试在 personal/attachments/ 寻找
                $attP = Join-Path $personalAttDir $fClean
                if (Test-Path $attP) {
                    $resultFiles += (Resolve-Path $attP).Path
                } else {
                    Write-Host "[ERROR] 附件文件未找到: $fClean" -ForegroundColor Red
                    exit 1
                }
            }
        }
    }
    
    $uniqueFiles = @($resultFiles | Select-Object -Unique)
    
    # 体积预检
    $totalBytes = 0
    foreach ($f in $uniqueFiles) { $totalBytes += (Get-Item $f).Length }
    $totalMB = [math]::Round($totalBytes / 1MB, 2)
    
    $maxMB = if ($script:Profile.safety_limits.max_attachment_total_mb) { [double]$script:Profile.safety_limits.max_attachment_total_mb } else { 10.0 }
    $warnMB = if ($script:Profile.safety_limits.warning_attachment_mb) { [double]$script:Profile.safety_limits.warning_attachment_mb } else { 5.0 }
    
    if ($totalMB -gt $maxMB) {
        Write-Host "[ERROR] 附件总大小 ($totalMB MB) 超过限制 ($maxMB MB)，极易被拦截拒收！" -ForegroundColor Red
        exit 1
    } elseif ($totalMB -gt $warnMB) {
        Write-Host "[WARN] 附件总大小为 $totalMB MB，建议压缩至 $warnMB MB 以内保证到达率。" -ForegroundColor Yellow
    }

    # 规范化附件命名校验
    foreach ($f in $uniqueFiles) {
        $fName = Split-Path -Leaf $f
        if ($fName -match '(新建|未命名|副本|\(\d+\)|temp|test)') {
            Write-Host "[WARN] 附件名称可能不规范: '$fName'！强烈建议重命名为 '姓名-材料名.pdf' (例如: 张三-简历.pdf)。" -ForegroundColor Yellow
        }
    }
    
    return $uniqueFiles
}

# ==================== 5. 参数解析与执行 ====================

$csv = ""; $template = "A"; $attachArgs = @(); $dryRun = $false; $interval = 30; $via = ""
$defaultAttach = $false; $force = $false; $connection = ""; $draft = $false

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--draft" { $draft = $true }
        "--csv" { $csv = $args[++$i] }
        "--template" { $template = $args[++$i] }
        "--attach" { $attachArgs += $args[++$i] }
        "--default-attach" { $defaultAttach = $true }
        "--dry-run" { $dryRun = $true }
        "--force" { $force = $true }
        "--interval" { $interval = [int]$args[++$i] }
        "--via" { $via = $args[++$i] }
        "--connection" { $connection = $args[++$i] }
    }
    $i++
}

# 默认 CSV 智能推断 (若未指定，优先使用 personal/contacts.csv)
if (-not $csv) {
    $pContacts = Join-Path $script:PERSONAL_DIR "contacts.csv"
    if (Test-Path $pContacts) {
        $csv = $pContacts
    } else {
        $sampleContacts = Join-Path $script:CORE_SCHEMAS "contacts.sample.csv"
        Write-Host ""
        Write-Host "通用学术推免套磁信智能批量发送引擎 (Core Engine)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "用法: .\batch-send.ps1 --csv <contacts.csv> [选项]" -ForegroundColor White
        Write-Host "选项: --template <A|B|C|D>, --via <edu|qq|netease>, --attach <file1,file2>, --dry-run" -ForegroundColor DarkGray
        Write-Host "当前 personal/contacts.csv 尚未创建，可参考规范样例: $sampleContacts" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

if (-not (Test-Path $csv)) {
    $candidates = @(
        (Join-Path $script:SKILL_DIR $csv),
        (Join-Path $script:PERSONAL_DIR $csv),
        (Join-Path $script:PERSONAL_DIR (Split-Path -Leaf $csv)),
        (Join-Path $script:CORE_SCHEMAS $csv),
        (Join-Path $script:CORE_SCHEMAS (Split-Path -Leaf $csv))
    )
    $found = $null
    foreach ($c in $candidates) {
        if (Test-Path $c) { $found = $c; break }
    }
    if ($found) {
        $csv = $found
    } else {
        Write-Host "[ERROR] 未找到通讯录 CSV: $csv" -ForegroundColor Red
        exit 1
    }
}

# 强校验发信通道
if (-not $dryRun) {
    if (-not $via) {
        Write-Host ""
        Write-Host "=================================================================" -ForegroundColor Red
        Write-Host "[ERROR] 真实发信必须显式通过 --via <edu|qq|netease> 指定发信邮箱！" -ForegroundColor Red
        Write-Host "严禁擅自猜测或代选。请明确确认您希望使用哪个邮箱投递本次套磁信。" -ForegroundColor Yellow
        Write-Host "=================================================================" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    $viaNorm = $via.ToLower()
    if ($viaNorm -in @("163", "wangyi")) { $viaNorm = "netease" }
    if ($viaNorm -in @("campus", "school")) { $viaNorm = "edu" }
    if ($viaNorm -notin @("edu", "qq", "netease")) {
        Write-Host "[ERROR] 不支持的发信通道: '$via'。仅支持 edu (校园邮箱), qq, netease。" -ForegroundColor Red
        exit 1
    }
    $via = $viaNorm
}

$finalAttachments = Resolve-Attachments -AttachInputs $attachArgs -DefaultAttach:$defaultAttach
Init-Tracking

$rows = Import-Csv $csv
$total = @($rows).Count

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [BATCH] 启动套磁任务: 共 $total 位导师 | 模板基准: $template | 模式: $(if($dryRun){'【DRY-RUN 预览】'}else{'【真实投递】'})" -ForegroundColor Cyan
Write-Host " 当前画像: $script:ACTIVE_PROFILE_PATH" -ForegroundColor DarkGray
if ($finalAttachments.Count -gt 0) {
    Write-Host " 挂载附件 ($($finalAttachments.Count) 个):" -ForegroundColor DarkGray
    foreach ($fa in $finalAttachments) {
        $faName = Split-Path -Leaf $fa
        $faSize = [math]::Round((Get-Item $fa).Length / 1KB, 1)
        Write-Host "   - $faName (${faSize} KB)" -ForegroundColor DarkGray
    }
}
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$count = 0
$sentSuccess = 0
$skippedCount = 0

foreach ($row in $rows) {
    $count++
    $name = $row.name
    $email = $row.email
    $org = if ($row.org) { $row.org } else { "" }
    $direction = if ($row.direction) { $row.direction } else { "" }
    $interest = if ($row.research_interest) { $row.research_interest } else { $direction }
    $tplType = if ($row.template) { $row.template } else { $template }
    $paper = if ($row.PSObject.Properties['paper'] -and $row.paper) { $row.paper } else { "" }
    $connText = if ($row.PSObject.Properties['connection'] -and $row.connection) { $row.connection } elseif ($connection) { $connection } else { "" }
    
    $title = if ($row.PSObject.Properties['title'] -and $row.title) { $row.title } else { "老师" }
    if ($name.EndsWith("老师") -or $name.EndsWith("教授") -or $name.EndsWith("研究员")) { $title = "" }
    
    $nameEn = $name
    if ($name -match "^(Prof\.|Dr\.)\s*(.+)") { $nameEn = $matches[2] }

    Write-Host "[$count/$total] $name <$email> ($org) — 模板 $tplType" -ForegroundColor White

    # 查重检查 (防手滑)
    $recentSent = Check-RecentSent -Recipient $email
    if ($recentSent -and -not $force) {
        Write-Host "  [DEDUP SKIP] 过去 14 天内已向该邮箱发过信 ($($recentSent.date))，已自动跳过防重复。" -ForegroundColor Yellow
        Write-Host "               若需强制发送，请添加 --force 参数。" -ForegroundColor DarkGray
        $skippedCount++
        Write-Host ""
        continue
    }

    $tplData = Get-TemplateContent -Type $tplType
    
    $attachNote = if ($finalAttachments.Count -gt 1) { "附有我的个人简历、陈述及相关材料，方便您更好地了解我。" } else { "附有一份个人简历与陈述，方便您更好地了解我。" }
    $attachNoteEn = "I have attached my CV, personal statement, and related materials for your review."

    $vars = @{
        "NAME" = $name
        "NAME_EN" = $nameEn
        "TITLE" = $title
        "ORG" = $org
        "DIRECTION" = $direction
        "INTEREST" = $interest
        "PAPER" = $paper
        "CONNECTION" = if ($connText) { $connText } else { "对您的${interest}相关研究很感兴趣。" }
        "ATTACH_NOTE" = $attachNote
        "ATTACH_NOTE_EN" = $attachNoteEn
        "MY_NAME" = $script:MY_NAME
        "MY_NAME_EN" = $script:MY_NAME_EN
        "MY_SCHOOL" = $script:MY_SCHOOL
        "MY_SCHOOL_EN" = $script:MY_SCHOOL_EN
        "MY_COLLEGE" = $script:MY_COLLEGE
        "MY_COLLEGE_EN" = $script:MY_COLLEGE_EN
        "MY_MAJOR" = $script:MY_MAJOR
        "MY_MAJOR_EN" = $script:MY_MAJOR_EN
        "MY_EMAIL" = $script:MY_EMAIL
        "MY_INTENT" = $script:MY_INTENT
        "ADVISOR" = $script:ADVISOR
        "PROJECT_NAME" = $script:PROJECT_NAME
        "EXPERIENCE_SUMMARY" = $script:EXP_SUMMARY
        "EXPERIENCE_SUMMARY_EN" = $script:EXP_SUMMARY_EN
    }

    $subject = Render-MailText -Text $tplData.Subject -Vars $vars
    $body = Render-MailText -Text $tplData.Body -Vars $vars

    # 占位符残留一票否决
    $unresolved = [regex]::Matches("$subject $body", '\{\{[A-Za-z0-9_]+\}\}') | ForEach-Object { $_.Value }
    if (@($unresolved).Count -gt 0) {
        Write-Host "  [VALIDATION ERROR] 检测到未替换的占位符 ($($unresolved -join ', '))，为防失误已拦截跳过！" -ForegroundColor Red
        $skippedCount++
        Write-Host ""
        continue
    }

    if ($dryRun) {
        Write-Host "  Subject: $subject" -ForegroundColor DarkCyan
        Write-Host "  Template Source: $(Split-Path -Leaf $tplData.Source)" -ForegroundColor DarkGray
        Write-Host "  Body Preview:" -ForegroundColor DarkGray
        $body.Split("`n") | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Host ""
        continue
    }

    if (-not (Test-Path $script:MAIL_ENGINE)) {
        Write-Host "  [ERROR] 底层发信引擎未找到: $script:MAIL_ENGINE" -ForegroundColor Red
        continue
    }

    $sendArgs = @("-Account", $via, "send", "--to", $email, "--subject", $subject, "--body", $body, "--no-sig")
    foreach ($att in $finalAttachments) {
        $sendArgs += @("--attach", $att)
    }
    if ($draft) { $sendArgs += @("--draft") }

    $result = & powershell -ExecutionPolicy Bypass -File $script:MAIL_ENGINE @sendArgs 2>&1
    $isDraftSaved = ($result -match '\[DRAFT\]')
    $success = ($result -match '"success":\s*true') -or ($result -match 'Message sent successfully') -or $isDraftSaved

    if ($isDraftSaved) {
        Write-Host "  → 已安全存入草稿箱 ✓ (邮箱: $via)" -ForegroundColor Green
        Write-Tracking -Recipient $email -Name $name -Org $org -Subject $subject -Template $tplType -Status "draft" -SentVia $via
        $sentSuccess++
    } elseif ($success) {
        Write-Host "  → 发送成功 ✓ (通道: $via)" -ForegroundColor Green
        Write-Tracking -Recipient $email -Name $name -Org $org -Subject $subject -Template $tplType -Status "sent" -SentVia $via
        $sentSuccess++
    } else {
        Write-Host "  → 操作失败 ✗ (通道: $via)" -ForegroundColor Red
        $result | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Tracking -Recipient $email -Name $name -Org $org -Subject $subject -Template $tplType -Status "failed" -SentVia $via
    }

    # 随机时延防封 (草稿模式无需长延时)
    if ($count -lt $total -and -not $draft) {
        $wait = Get-Random -Minimum $interval -Maximum ($interval * 2)
        Write-Host "  安全风控等待 ${wait}s (防高校垃圾拦截)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $wait
    }
    Write-Host ""
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [SUMMARY] 任务完成: 总计 $total 位 | 成功 $sentSuccess | 跳过(查重) $skippedCount | 模式: $(if($dryRun){'预览完成'}else{'投递完成'})" -ForegroundColor Cyan
Write-Host " 追踪日志已记录在私人隔离区: $script:TRACKING_FILE" -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Cyan
