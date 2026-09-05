<#
.SYNOPSIS
  单封推免套磁信草稿智能生成器 (Create-Draft Engine)
.DESCRIPTION
  根据导师信息与特调模板，生成个性化套磁信，并直接保存至指定邮箱的草稿箱（绝不直接发送）。
  
  参数：
    --to <邮箱地址>          导师邮箱 (必填)
    --name <姓名>            导师姓名 (必填)
    --title <称谓>           职称/称谓 (默认: 老师 / 研究员 / 教授)
    --org <单位>             导师所在院所/大学
    --interest <研究课题>     关注的具体研究方向/课题关键词
    --paper <论文代表作>     关注的导师近期论文关键词
    --connection <连接契机>   个性化契机 (针对模板B)
    --template <A|B|C|D>     选用模板 (默认: A)
    --via <edu|qq|netease>   目标草稿箱所在邮箱 (默认: edu)
    --attach <文件列表>      挂载附件路径 (逗号分隔)
    --default-attach         自动挂载 profile.json 中的默认简历与陈述

  用法示例：
    powershell -ExecutionPolicy Bypass -File .\create-draft.ps1 `
      --to "prof@example.edu.cn" --name "王教授" --title "教授" --org "示例大学计算机学院" `
      --interest "分布式系统与高并发架构" --template A --via edu
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ENGINE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:CORE_DIR = Split-Path -Parent $script:ENGINE_DIR
$script:SKILL_DIR = Split-Path -Parent $script:CORE_DIR
$script:PROJECT_ROOT = Split-Path -Parent $script:SKILL_DIR

$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:CORE_TEMPLATES = Join-Path $script:CORE_DIR "templates"
$script:CORE_SCHEMAS = Join-Path $script:CORE_DIR "schemas"
$script:MAIL_SERVICE = Join-Path $script:PROJECT_ROOT "mail-ai"

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
$script:EXP_SUMMARY_EN = if ($script:Profile.research_background.experience_summary_en) { $script:Profile.research_background.experience_summary_en } else { "I have independent research experience." }

# ==================== 2. 模板解析 ====================

function Get-TemplateContent {
    param([string]$Type)
    $typeUpper = $Type.ToUpper()
    $templateFile = $null
    
    $personalTplDir = Join-Path $script:PERSONAL_DIR "templates"
    if (Test-Path $personalTplDir) {
        $pMatches = Get-ChildItem -Path $personalTplDir | Where-Object { $_.Name -match "^(template_|standard_)?$typeUpper(_|\.|\$)" }
        if ($pMatches.Count -gt 0) { $templateFile = $pMatches[0].FullName }
    }
    if (-not $templateFile -and (Test-Path $script:CORE_TEMPLATES)) {
        $cMatches = Get-ChildItem -Path $script:CORE_TEMPLATES | Where-Object { $_.Name -match "^(standard_|template_)?$typeUpper(_|\.|\$)" }
        if ($cMatches.Count -gt 0) { $templateFile = $cMatches[0].FullName }
    }
    
    if ($templateFile -and (Test-Path $templateFile)) {
        $raw = Get-Content $templateFile -Raw -Encoding UTF8
        $subj = ""; $body = ""
        if ($raw -match "(?ms)SUBJECT:\s*(.*?)\r?\n---BODY---\r?\n(.*)") {
            $subj = $matches[1].Trim()
            $body = $matches[2]
        } else {
            $body = $raw
            $subj = "研究生申请信——$script:MY_SCHOOL$script:MY_MAJOR$script:MY_NAME"
        }
        return @{ Subject = $subj; Body = $body; Source = $templateFile }
    }
    return @{
        Subject = "研究生申请信——$script:MY_SCHOOL$script:MY_MAJOR$script:MY_NAME"
        Body = "{{NAME}}{{TITLE}}您好，我是$script:MY_SCHOOL$script:MY_MAJOR本科生$script:MY_NAME。对您的{{INTEREST}}研究很感兴趣。附简历供审阅。祝好！"
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

# ==================== 3. 附件处理 ====================

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
            if (Test-Path $fClean) { $resultFiles += (Resolve-Path $fClean).Path }
            else {
                $attP = Join-Path $personalAttDir $fClean
                if (Test-Path $attP) { $resultFiles += (Resolve-Path $attP).Path }
                else {
                    Write-Host "[WARN] 附件文件未找到: $fClean" -ForegroundColor Yellow
                }
            }
        }
    }
    return @($resultFiles | Select-Object -Unique)
}

# ==================== 4. 参数解析 ====================

$to = ""; $name = ""; $title = ""; $org = ""; $interest = ""; $direction = ""
$paper = ""; $connection = ""; $template = "A"; $via = "edu"
$attachInputs = @(); $defaultAttach = $false; $noAttach = $false

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--to" { $to = $args[++$i] }
        "--name" { $name = $args[++$i] }
        "--title" { $title = $args[++$i] }
        "--org" { $org = $args[++$i] }
        "--interest" { $interest = $args[++$i] }
        "--direction" { $direction = $args[++$i] }
        "--paper" { $paper = $args[++$i] }
        "--connection" { $connection = $args[++$i] }
        "--template" { $template = $args[++$i] }
        "--via" { $via = $args[++$i].ToLower() }
        "--attach" { $attachInputs += $args[++$i] }
        "--default-attach" { $defaultAttach = $true }
        "--no-attach" { $noAttach = $true }
    }
    $i++
}

if (-not $to -or -not $name) {
    Write-Host ""
    Write-Host "单封推免套磁信草稿生成器 (create-draft.ps1)" -ForegroundColor Cyan
    Write-Host "用法:" -ForegroundColor White
    Write-Host "  .\create-draft.ps1 --to <email> --name <导师姓名> [选项]"
    Write-Host ""
    Write-Host "常用选项:" -ForegroundColor DarkGray
    Write-Host "  --title <称谓>       导师职称（如：研究员/教授，默认：老师）"
    Write-Host "  --org <单位>         所属单位（如：示例大学计算机学院）"
    Write-Host "  --interest <课题>    导师具体研究方向/课题关键词"
    Write-Host "  --connection <契机>  与导师的连接契机（适用于模板B）"
    Write-Host "  --template <A|B|C|D> 选用模板（默认：A）"
    Write-Host "  --via <campus|qq|netease> 保存至哪个邮箱的草稿箱（默认：edu）"
    Write-Host "  --attach <files>     挂载附件（逗号分隔）"
    Write-Host "  --default-attach     自动挂载 profile 中的默认简历与陈述"
    Write-Host ""
    exit 1
}

# 规整通道别名
if ($via -in @("163", "wangyi")) { $via = "netease" }
if ($via -notin @("edu", "qq", "netease")) { $via = "edu" }

# 智能挂载：如果未传 --attach 且未指定 --no-attach，默认自动载入 profile.json 中的简历
if (-not $noAttach -and $attachInputs.Count -eq 0) {
    $defaultAttach = $true
}
$resolvedAttachments = Resolve-Attachments -AttachInputs $attachInputs -DefaultAttach:$defaultAttach

# 称谓与英文名
if (-not $title) { $title = "老师" }
if ($name.EndsWith("老师") -or $name.EndsWith("教授") -or $name.EndsWith("研究员")) { $title = "" }
$nameEn = $name
if ($name -match "^(Prof\.|Dr\.)\s*(.+)") { $nameEn = $matches[2] }

$tplData = Get-TemplateContent -Type $template

$attachNote = if ($resolvedAttachments.Count -gt 1) { 
    "附有我的个人简历、陈述及相关材料，方便您更好地了解我。" 
} elseif ($resolvedAttachments.Count -eq 1) { 
    "附有一份个人简历与陈述材料，方便您更好地了解我。" 
} else { 
    "" 
}
$attachNoteEn = if ($resolvedAttachments.Count -gt 0) { 
    "I have attached my CV, personal statement, and related materials for your review." 
} else { 
    "" 
}

$vars = @{
    "NAME" = $name
    "NAME_EN" = $nameEn
    "TITLE" = $title
    "ORG" = $org
    "DIRECTION" = if ($direction) { $direction } else { $interest }
    "INTEREST" = $interest
    "PAPER" = $paper
    "CONNECTION" = if ($connection) { $connection } else { "对您的${interest}相关研究很感兴趣。" }
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

$renderedSubject = Render-MailText -Text $tplData.Subject -Vars $vars
$renderedBody = Render-MailText -Text $tplData.Body -Vars $vars

# 标点符号与空白规整：将英文半角双引号规范化为中文学术双引号，清理因空附件注记可能产生的多余空行
$renderedBody = $renderedBody -replace '(?<!\w)"([^"

]+)"', '“$1”'
$renderedBody = $renderedBody -replace '(
?
){3,}', "`r`n`r`n"

# ==================== 4.5 五重质量与风控校验 ====================

# 1. 邮箱有效性与域名校验
if ($to -notmatch '^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$') {
    Write-Host "[ERROR] 导师邮箱格式不合法: '$to'，请仔细核查！" -ForegroundColor Red
    exit 1
}
if ($to -notmatch '(\.edu\.cn|\.ac\.cn|\.edu|\.org|\.cn)$') {
    Write-Host "[WARN] 目标邮箱并非高校/学术机构域名 ($to)，建议优先使用导师官方主页公布的工作邮箱。" -ForegroundColor Yellow
}

# 2. 占位符残留一票否决 (绝对安全红线)
$unresolvedSubj = [regex]::Matches($renderedSubject, '\{\{[A-Za-z0-9_]+\}\}') | ForEach-Object { $_.Value }
$unresolvedBody = [regex]::Matches($renderedBody, '\{\{[A-Za-z0-9_]+\}\}') | ForEach-Object { $_.Value }
$allUnresolved = @($unresolvedSubj + $unresolvedBody | Select-Object -Unique)

if ($allUnresolved.Count -gt 0) {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Red
    Write-Host "[VALIDATION ERROR] 正文中检测到残留的未替换占位符！" -ForegroundColor Red
    Write-Host "残留项: $($allUnresolved -join ', ')" -ForegroundColor Yellow
    Write-Host "为防止给导师发送半成品邮件引发严重失误，系统已强行终止保存！" -ForegroundColor Red
    Write-Host "=================================================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# 3. 篇幅与学术关键词校验
if ($renderedBody.Length -lt 80) {
    Write-Host "[WARN] 邮件正文字数过少 ($($renderedBody.Length) 字)，缺乏必要学术细节，建议补充科研背景。" -ForegroundColor Yellow
}
if ($interest -eq "" -and $paper -eq "") {
    Write-Host "[WARN] 导师研究课题与代表作均为空，内容可能过于泛化。强烈建议补充导师近 1-2 年发表论文或课题关键词。" -ForegroundColor Yellow
}

# 4. 附件专业命名校验
foreach ($att in $resolvedAttachments) {
    $attName = Split-Path -Leaf $att
    if ($attName -match '(新建|未命名|副本|\(\d+\)|temp|test)') {
        Write-Host "[WARN] 附件名称可能不规范: '$attName'！强烈建议重命名为 '姓名-材料名.pdf' (例如: 张三-简历.pdf)，展现严谨学术态度。" -ForegroundColor Yellow
    }
}

# ==================== 5. 存入目标邮箱草稿箱 ====================

$draftsDir = Join-Path $script:MAIL_SERVICE "profiles\$via\drafts"
if (-not (Test-Path $draftsDir)) {
    New-Item -ItemType Directory -Path $draftsDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeName = $name -replace '[^\w\u4e00-\u9fa5]', '_'
$draftFileName = "draft_${safeName}_${timestamp}.json"
$draftFilePath = Join-Path $draftsDir $draftFileName

$draftObj = @{
    CreatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Account = $via
    To = $to
    Name = $name
    Org = $org
    Subject = $renderedSubject
    Body = $renderedBody
    Attachments = $resolvedAttachments
    Status = "draft"
    Template = $template
}

$draftObj | ConvertTo-Json -Depth 5 | Set-Content -Path $draftFilePath -Encoding UTF8

# 自动同步记录到 personal/tracking.csv，形成闭环追踪
$trackingHelper = Join-Path $script:ENGINE_DIR "tracking-helper.ps1"
if (Test-Path $trackingHelper) {
    . $trackingHelper
    Write-TrackingRecord -Recipient $to -Name $name -Org $org -Subject $renderedSubject -Template $template -Status "draft" -SentVia $via
}

# 同步推送至云端 IMAP 草稿箱 (支持在网页端或客户端中即时查看与编辑)
$mailEngine = Join-Path $script:MAIL_SERVICE "core\mail-engine.ps1"
$cloudSyncSuccess = $false
if (Test-Path $mailEngine) {
    $engineArgs = @("-Account", $via, "send", "--to", $to, "--subject", $renderedSubject, "--body", $renderedBody, "--draft", "--no-sig")
    if ($resolvedAttachments.Count -gt 0) {
        $engineArgs += @("--attach", ($resolvedAttachments -join ","))
    }
    $syncOut = & powershell -ExecutionPolicy Bypass -File $mailEngine @engineArgs 2>&1
    if ($syncOut -match "云端草稿箱同步成功") {
        $cloudSyncSuccess = $true
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " [DRAFT SAVED] 套磁信草稿已成功存入草稿箱！(未发送)" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "  收件人:   $name <$to> ($org)" -ForegroundColor White
Write-Host "  主题:     $renderedSubject" -ForegroundColor Cyan
Write-Host "  保存邮箱: $via 邮箱草稿箱" -ForegroundColor White
Write-Host "  本地草稿: $draftFilePath" -ForegroundColor DarkGray
if ($cloudSyncSuccess) {
    Write-Host "  云端同步: $via 邮箱云端草稿箱已同步 ✓ (可直接登录 校园邮箱网页端 查看)" -ForegroundColor Green
}
if ($resolvedAttachments.Count -gt 0) {
    Write-Host "  挂载附件: $($resolvedAttachments -join '; ')" -ForegroundColor DarkGray
}
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "【正文预览】:" -ForegroundColor Yellow
$renderedBody.Split("`n") | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " 📢 提示：邮件已安全保存在草稿箱中，默认不会直接发送。" -ForegroundColor Yellow
Write-Host "    您可以在客户端/网页端查看并最终发送；若需由 AI 代发，请在单独对话中明确要求，并在二次确认后执行。" -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""
