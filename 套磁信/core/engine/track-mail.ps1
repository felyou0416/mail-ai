<#
.SYNOPSIS
  通用学术推免套磁信回复追踪与 Follow-up 闭环引擎 (Universal Track-Mail Engine)
.DESCRIPTION
  特性：
    1. 跨邮箱联合检索：跨通道联合检索学术收件箱，精准判定导师是否已回信。
    2. 私人数据安全隔离：默认读取并操作 personal/tracking.csv，生成个人专属 personal/followup.csv。
    3. 智能状态分类：已回复、需跟进 (≥7天未回)、等待中、已发跟进信 (模板D)。
    4. 零隐私代码：无个人敏感信息，适合共享复用。
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ENGINE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:CORE_DIR = Split-Path -Parent $script:ENGINE_DIR
$script:SKILL_DIR = Split-Path -Parent $script:CORE_DIR
$script:PROJECT_ROOT = Split-Path -Parent $script:SKILL_DIR

$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:TRACKING_FILE = Join-Path $script:PERSONAL_DIR "tracking.csv"
if (-not (Test-Path $script:TRACKING_FILE)) {
    # 回退检查
    $fb = Join-Path $script:SKILL_DIR "tracking.csv"
    if (Test-Path $fb) { $script:TRACKING_FILE = $fb }
}

$script:ENGINE = Join-Path $script:PROJECT_ROOT "mail-service\core\mail-engine.ps1"

# 参数解析
$daysFilter = 0; $needsFollowup = $false; $generateFollowup = $false
$exportFile = ""; $accountFilter = ""
$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--days" { $daysFilter = [int]$args[++$i] }
        "--needs-followup" { $needsFollowup = $true }
        "--generate-followup" { $generateFollowup = $true }
        "--export" { $exportFile = $args[++$i] }
        "--account" { $accountFilter = $args[++$i].ToLower() }
    }
    $i++
}

if (-not (Test-Path $script:TRACKING_FILE)) {
    Write-Host ""
    Write-Host "[INFO] 跟踪日志尚未生成: $script:TRACKING_FILE" -ForegroundColor Yellow
    Write-Host "       请先执行 batch-send.ps1 投递套磁信后自动在此追踪。" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

$tracks = Import-Csv $script:TRACKING_FILE
$totalRecords = @($tracks).Count

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 推免套磁信智能追踪仪表盘 (Universal Track Engine)" -ForegroundColor Cyan
Write-Host " 追踪日志: $script:TRACKING_FILE (共 $totalRecords 条投递记录)" -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

if ($totalRecords -eq 0) {
    Write-Host "  暂无发信记录。投递后将在此自动追踪回复状态。" -ForegroundColor Yellow
    exit 0
}

$sentRecipients = @($tracks | Where-Object { $_.status -ieq "sent" } | Select-Object -ExpandProperty recipient -Unique)
$replyMap = @{}

if (Test-Path $script:ENGINE) {
    $accountsToCheck = if ($accountFilter) { @($accountFilter) } else { @("edu", "qq", "netease") }
    Write-Host "[CHECK] 正在跨邮箱联合检索学术收件箱中的导师来信 (通道: $($accountsToCheck -join ', '))..." -ForegroundColor Yellow
    
    foreach ($acc in $accountsToCheck) {
        foreach ($recipient in $sentRecipients) {
            if ($replyMap.ContainsKey($recipient)) { continue }
            $searchRes = & powershell -ExecutionPolicy Bypass -File $script:ENGINE -Account $acc search --from $recipient --limit 5 2>&1
            $searchOut = $searchRes -join "`n"
            if ($searchOut -match '"uid"') {
                $replyMap[$recipient] = @{
                    Account = $acc
                    Status = "已回复"
                }
            }
        }
    }
    Write-Host "        跨邮箱检索完成。" -ForegroundColor DarkGray
    Write-Host ""
}

$report = @()
$followupList = @()

foreach ($track in $tracks) {
    $sentDate = try { [datetime]::Parse($track.date) } catch { Get-Date }
    $daysAgo = [int]((Get-Date) - $sentDate).TotalDays
    
    $isReplied = $replyMap.ContainsKey($track.recipient)
    $replyInfo = if ($isReplied) { $replyMap[$track.recipient] } else { $null }
    
    $isFollowupTpl = ($track.template -ieq "D")
    $needsFollow = (-not $isReplied) -and ($daysAgo -ge 7) -and ($track.status -ieq "sent") -and (-not $isFollowupTpl)

    $statusStr = if ($isReplied) { "已回复 ✓ ($($replyInfo.Account))" }
                 elseif ($isFollowupTpl) { "已发跟进信" }
                 elseif ($needsFollow) { "需跟进 (≥7天未回)" }
                 elseif ($track.status -ieq "sent") { "等待中 (${daysAgo}天)" }
                 else { "发送失败" }

    $item = [PSCustomObject]@{
        Date = $track.date
        Name = $track.name
        Org = $track.org
        Email = $track.recipient
        Subject = $track.subject
        Template = $track.template
        DaysAgo = $daysAgo
        Status = $statusStr
        Via = $track.sent_via
    }
    $report += $item

    if ($needsFollow) {
        $followupList += [PSCustomObject]@{
            name = $track.name
            title = "老师"
            email = $track.recipient
            org = $track.org
            direction = ""
            research_interest = ""
            template = "D"
            connection = ""
            paper = ""
        }
    }
}

$filtered = $report
if ($needsFollowup) {
    $filtered = $report | Where-Object { $_.Status -match "需跟进" }
}
if ($daysFilter -gt 0) {
    $filtered = $filtered | Where-Object { $_.DaysAgo -ge $daysFilter -and $_.Status -notmatch "已回复" }
}

if (@($filtered).Count -eq 0) {
    Write-Host "  没有匹配的筛选记录。" -ForegroundColor Green
} else {
    $filtered | Format-Table -AutoSize
}

$repliedCount = @($report | Where-Object { $_.Status -match "已回复" }).Count
$waitingCount = @($report | Where-Object { $_.Status -match "等待中" }).Count
$followCount = @($report | Where-Object { $_.Status -match "需跟进" }).Count
$followedUpCount = @($report | Where-Object { $_.Status -match "已发跟进信" }).Count
$failedCount = @($report | Where-Object { $_.Status -match "发送失败" }).Count

Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " 统计汇总:" -ForegroundColor Cyan
Write-Host "   已回复: $repliedCount 封 | 等待中: $waitingCount 封 | 需跟进: $followCount 封 | 已跟进: $followedUpCount 封 | 失败: $failedCount 封" -ForegroundColor White
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if ($generateFollowup -or $exportFile) {
    $targetCsv = if ($exportFile) { $exportFile } else { (Join-Path $script:PERSONAL_DIR "followup.csv") }
    if ($followupList.Count -gt 0) {
        $followupList | Export-Csv $targetCsv -NoTypeInformation -Encoding UTF8
        Write-Host " [FOLLOW-UP] 已成功为 $($followupList.Count) 位需跟进导师生成专用通讯录: $targetCsv" -ForegroundColor Green
        Write-Host "             接力发送命令: powershell -ExecutionPolicy Bypass -File .\batch-send.ps1 --csv `"$targetCsv`" --template D --via edu --dry-run" -ForegroundColor Yellow
    } else {
        Write-Host " [FOLLOW-UP] 当前无符合条件的需跟进导师（全部均在 7 天内或已回复）。" -ForegroundColor Green
    }
    Write-Host ""
} elseif ($followCount -gt 0) {
    Write-Host " [提示] 有 $followCount 封套磁信已超过 7 天未回复，建议发送 Follow-up 邮件！" -ForegroundColor Yellow
    Write-Host "        执行命令一键生成待跟进名单: powershell -ExecutionPolicy Bypass -File .\track-mail.ps1 --generate-followup" -ForegroundColor Yellow
    Write-Host ""
}
