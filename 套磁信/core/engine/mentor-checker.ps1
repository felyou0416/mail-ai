<#
.SYNOPSIS
  导师风控查重与同组冲突预警器 (Mentor Conflict Checker)
.DESCRIPTION
  在套磁前一键体检：
  1. 邮箱真实性与高校学术域名校验
  2. 14 天内防手滑查重
  3. 14 天内同机构/同课题组多投预警（防同组双投尴尬）
  4. 现有档案速查
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ENGINE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:CORE_DIR = Split-Path -Parent $script:ENGINE_DIR
$script:SKILL_DIR = Split-Path -Parent $script:CORE_DIR

$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:TRACKING_FILE = Join-Path $script:PERSONAL_DIR "tracking.csv"
$script:CONTACTS_FILE = Join-Path $script:PERSONAL_DIR "contacts.csv"

$name = ""; $org = ""; $email = ""; $isJson = $false

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--name" { $name = $args[++$i] }
        "--org" { $org = $args[++$i] }
        "--email" { $email = $args[++$i] }
        "-Json" { $isJson = $true }
        "--json" { $isJson = $true }
        default {
            if (-not $name -and -not $args[$i].StartsWith("-")) {
                $name = $args[$i]
            } elseif (-not $org -and -not $args[$i].StartsWith("-")) {
                $org = $args[$i]
            }
        }
    }
    $i++
}

if (-not $name -and -not $email -and -not $org) {
    Write-Host ""
    Write-Host "导师风控查重与同组冲突预警器 (mentor-checker.ps1)" -ForegroundColor Cyan
    Write-Host "用法:" -ForegroundColor White
    Write-Host "  .\mail.ps1 check-mentor <导师姓名> [单位] [--email <邮箱>]"
    Write-Host "  .\mail.ps1 check-mentor --name 王教授 --org 示例大学计算机学院"
    Write-Host ""
    exit 0
}


$diagResult = @{
    name = $name
    org = $org
    email = $email
    safe = $true
    duplicate = $false
    collision = $false
    warnings = @()
    matched_contact = $null
}

if ($isJson) {
    # Check duplicate in tracking
    if (Test-Path $script:TRACKING_FILE) {
        try {
            $tracks = @(Import-Csv $script:TRACKING_FILE)
            $now = Get-Date
            foreach ($t in $tracks) {
                $mDate = [datetime]$t.Date
                if (($now - $mDate).TotalDays -le 14) {
                    if (($name -and $t.Name -eq $name) -or ($email -and $t.Email -eq $email)) {
                        $diagResult.duplicate = $true
                        $diagResult.safe = $false
                        $diagResult.warnings += "14 天内已向该导师发送或建档 ($($t.Date))"
                    }
                    if ($org -and $t.Org -eq $org -and $t.Name -ne $name) {
                        $diagResult.collision = $true
                        $diagResult.warnings += "14 天内曾联系同机构的 $($t.Name) 老师 ($($t.Date))"
                    }
                }
            }
        } catch {}
    }
    # Check contacts.csv
    if (Test-Path $script:CONTACTS_FILE) {
        try {
            $contacts = @(Import-Csv $script:CONTACTS_FILE)
            foreach ($c in $contacts) {
                if (($name -and $c.name -like "*$name*") -or ($email -and $c.email -eq $email)) {
                    $diagResult.matched_contact = @{
                        name = $c.name; title = $c.title; email = $c.email; org = $c.org
                        direction = $c.direction; template = $c.template
                    }
                    break
                }
            }
        } catch {}
    }
    $diagResult | ConvertTo-Json -Depth 5 -Compress:$false
    exit 0
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 导师风控查重体检报告: $(if ($name) { $name }) $(if ($org) { '(' + $org + ')' })" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. 邮箱格式与域名诊断
if ($email) {
    if ($email -notmatch '^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$') {
        Write-Host "  ✗ 邮箱格式: 邮箱 '$email' 非法，请仔细核对！" -ForegroundColor Red
    } elseif ($email -match '(\.edu\.cn|\.ac\.cn|\.edu|\.org|\.cn)$') {
        Write-Host "  ✓ 邮箱域名: 属于高校/科研机构官方域名 ($email)" -ForegroundColor Green
    } else {
        Write-Host "  ! 邮箱域名: 并非学术机构域名 ($email)，建议优先查找官网公布的校内工作邮箱" -ForegroundColor Yellow
    }
}

# 2. 14 天内防手滑查重
$trackingRecords = @()
if (Test-Path $script:TRACKING_FILE) {
    try { $trackingRecords = @(Import-Csv $script:TRACKING_FILE) } catch {}
}

$now = Get-Date
$foundSelf = $null
$sameOrgRecords = @()

foreach ($t in $trackingRecords) {
    $tDate = try { [datetime]::Parse($t.date) } catch { $now }
    $days = [int]($now - $tDate).TotalDays

    $isSamePerson = ($email -and $t.recipient -ieq $email) -or ($name -and $t.name -eq $name)
    if ($isSamePerson) {
        $foundSelf = @{ Record = $t; DaysAgo = $days }
    }

    $isSameOrg = $org -and $t.org -and ($t.org -like "*$org*" -or $org -like "*$($t.org)*")
    if ($isSameOrg -and -not $isSamePerson -and $days -le 14) {
        $sameOrgRecords += @{ Record = $t; DaysAgo = $days }
    }
}

if ($foundSelf) {
    $r = $foundSelf.Record
    $d = $foundSelf.DaysAgo
    Write-Host "  ✗ [重复提醒] $($r.name) 老师在 $d 天前已有记录：" -ForegroundColor Red
    Write-Host "      状态: $($r.status) | 主题: $($r.subject) | 日期: $($r.date)" -ForegroundColor DarkGray
    if ($r.status -eq "draft") {
        Write-Host "      建议：草稿箱中已有一封待发草稿，建议直接发送或编辑该草稿，无需重新新建。" -ForegroundColor Yellow
    } elseif ($r.status -eq "sent") {
        if ($d -lt 7) {
            Write-Host "      风控：投递未满 7 天 ($d 天)，请耐心等待导师回复，暂不建议重复发信！" -ForegroundColor Red
        } else {
            Write-Host "      建议：已发信 $d 天未回复，建议准备发送温和的 Follow-up (模板D) 邮件。" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ✓ [查重通过] 14 天内未向该导师投递或建档，无重复联系风险" -ForegroundColor Green
}

# 3. 同组/同单位多投预警
if ($sameOrgRecords.Count -gt 0) {
    Write-Host ""
    Write-Host "  ⚠️ [同单位/同组风险预警] 发现 14 天内曾联系同机构的其他老师：" -ForegroundColor Yellow
    foreach ($so in $sameOrgRecords) {
        $rec = $so.Record
        Write-Host "      - $($rec.name) ($($rec.org)) | 状态: $($rec.status) | $($so.DaysAgo) 天前 ($($rec.date))" -ForegroundColor DarkYellow
    }
    Write-Host "      学术建议：若两位老师隶属同一课题组/重点实验室，严禁未等拒绝同时联系两人！" -ForegroundColor Yellow
    Write-Host "                请优先等待第一位导师回复，或确认无名额后再行联系。" -ForegroundColor DarkGray
} else {
    if ($org) {
        Write-Host "  ✓ [同组安全] 14 天内未联系同单位 ($org) 的其他老师，无撞组风险" -ForegroundColor Green
    }
}

# 4. 通讯录已有资料速查
if (Test-Path $script:CONTACTS_FILE) {
    try {
        $contacts = @(Import-Csv $script:CONTACTS_FILE)
        $matchedContact = $contacts | Where-Object { ($name -and $_.name -eq $name) -or ($email -and $_.email -ieq $email) }
        if ($matchedContact) {
            $c = $matchedContact[0]
            Write-Host ""
            Write-Host "  [通讯录档案已收录]:" -ForegroundColor Cyan
            Write-Host "      姓名: $($c.name) $($c.title) | 邮箱: $($c.email) | 单位: $($c.org)" -ForegroundColor White
            Write-Host "      方向: $($c.direction) | 推荐模板: 模板 $($c.template)" -ForegroundColor DarkGray
            if ($c.connection) { Write-Host "      连接契机: $($c.connection)" -ForegroundColor DarkGray }
        }
    } catch {}
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
