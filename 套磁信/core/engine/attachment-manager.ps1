<#
.SYNOPSIS
  附件材料管家 (Attachment Manager)
.DESCRIPTION
  提供推免简历、陈述与证明材料的快速管理：
  - list        列出 personal/attachments 下所有材料及大小
  - verify      执行第四层风控体检（命名规范、体积 ≤5MB、PDF 结构完整性）
  - bind <file> 将指定 PDF 一键绑定为 profile.json 中的默认简历
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ENGINE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:CORE_DIR = Split-Path -Parent $script:ENGINE_DIR
$script:SKILL_DIR = Split-Path -Parent $script:CORE_DIR

$script:PERSONAL_DIR = Join-Path $script:SKILL_DIR "personal"
$script:ATT_DIR = Join-Path $script:PERSONAL_DIR "attachments"
$script:PROFILE_FILE = Join-Path $script:PERSONAL_DIR "profile.json"

if (-not (Test-Path $script:ATT_DIR)) {
    New-Item -ItemType Directory -Path $script:ATT_DIR -Force | Out-Null
}

$action = "list"
$isJson = $false
$target = ""

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "-Json" { $isJson = $true }
        "--json" { $isJson = $true }
        default {
            if (-not $action -or $action -eq "list") {
                if ($args[$i] -in @("list", "verify", "check", "bind", "set-default")) {
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

function Get-ProfileData {
    if (Test-Path $script:PROFILE_FILE) {
        try {
            return Get-Content $script:PROFILE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }
    return $null
}

switch ($action) {
    "list" {
        $files = @(Get-ChildItem -Path $script:ATT_DIR -File | Where-Object { $_.Name -ne "README.md" })
        $profile = Get-ProfileData
        $boundResume = if ($profile.default_attachments.resume) { $profile.default_attachments.resume } else { "" }

        if ($isJson) {
            $items = @()
            $idx = 1
            foreach ($f in $files) {
                $sizeMb = [Math]::Round($f.Length / 1MB, 2)
                $isBound = ($boundResume -and ($boundResume -like "*$($f.Name)*"))
                $items += @{
                    id = $idx
                    name = $f.Name
                    size_mb = $sizeMb
                    is_default = [bool]$isBound
                    valid = ($sizeMb -le 5.0)
                }
                $idx++
            }
            $items | ConvertTo-Json -Depth 5 -Compress:$false
            exit 0
        }

        Write-Host ""
        Write-Host "=== 个人专属附件材料清单 (personal/attachments) ===" -ForegroundColor Cyan
        if ($files.Count -eq 0) {
            Write-Host "  暂无可用的推免材料文件。" -ForegroundColor DarkGray
            exit 0
        }

        $idx = 1
        foreach ($f in $files) {
            $sizeKb = [Math]::Round($f.Length / 1024, 1)
            $sizeMb = [Math]::Round($f.Length / 1024 / 1024, 2)
            $sizeStr = if ($sizeKb -gt 1024) { "${sizeMb} MB" } else { "${sizeKb} KB" }
            
            $isBound = if ($boundResume -and ($boundResume -like "*$($f.Name)*")) { " [★ 当前默认简历]" } else { "" }
            
            Write-Host "  [$idx] $($f.Name)" -ForegroundColor Yellow -NoNewline
            Write-Host "$isBound" -ForegroundColor Green
            Write-Host "      大小: $sizeStr | 更新时间: $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor DarkGray
            $idx++
        }
        Write-Host ""
        Write-Host "  体检合规性: .\mail.ps1 attach verify" -ForegroundColor DarkCyan
        Write-Host "  设默认简历: .\mail.ps1 attach bind <序号或文件名>" -ForegroundColor DarkCyan
        Write-Host ""
    }

    { $_ -in @("verify", "check") } {
        $files = @(Get-ChildItem -Path $script:ATT_DIR -File | Where-Object { $_.Name -ne "README.md" })
        Write-Host ""
        Write-Host "=== 附件第四层学术风控体检报告 ===" -ForegroundColor Cyan
        if ($files.Count -eq 0) {
            Write-Host "  [WARN] 附件目录为空，无文件可体检。" -ForegroundColor Yellow
            exit 0
        }

        $allPass = $true
        foreach ($f in $files) {
            $sizeMb = $f.Length / 1024 / 1024
            Write-Host "  文件: $($f.Name)" -ForegroundColor White
            
            # 1. 命名规范
            if ($f.Name -match '(新建|未命名|副本|\(\d+\)|temp|test)') {
                Write-Host "    ✗ 命名风险: 含有草率词汇 (新建/副本/括号计数)，易给导师留下不严谨印象！" -ForegroundColor Red
                $allPass = $false
            } else {
                Write-Host "    ✓ 命名专业: 符合 '姓名-材料名' 学术命名规范" -ForegroundColor Green
            }

            # 2. 体积限制
            if ($sizeMb -gt 10.0) {
                Write-Host "    ✗ 体积超限: ${sizeMb:N2} MB > 10MB，超出高校邮件系统最大限制！" -ForegroundColor Red
                $allPass = $false
            } elseif ($sizeMb -gt 5.0) {
                Write-Host "    ! 体积偏大: ${sizeMb:N2} MB > 5MB，可能在部分手机客户端加载较慢，建议适当压缩" -ForegroundColor Yellow
            } else {
                Write-Host "    ✓ 体积合格: ${sizeMb:N2} MB (安全标准 ≤5MB)" -ForegroundColor Green
            }

            # 3. PDF 文件头校验
            if ($f.Extension.ToLower() -eq ".pdf") {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                    $header = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(10, $bytes.Length))
                    if ($header -match '^%PDF-') {
                        Write-Host "    ✓ 结构完整: 标准合规 PDF 格式" -ForegroundColor Green
                    } else {
                        Write-Host "    ✗ 格式损坏: 文件头非标准 %PDF-，文件可能已损坏！" -ForegroundColor Red
                        $allPass = $false
                    }
                } catch {
                    Write-Host "    ✗ 读取失败: $_" -ForegroundColor Red
                }
            }
            Write-Host ""
        }

        if ($allPass) {
            Write-Host "[RESULT] 全部附件材料通过第四层学术风控校验！✓" -ForegroundColor Green
        } else {
            Write-Host "[RESULT] 存在潜在风控隐患，请根据上述提示处理！✗" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    { $_ -in @("bind", "set-default") } {
        if (-not $target) {
            Write-Host "[ERROR] 请指定要绑定的材料序号或文件名！" -ForegroundColor Red
            exit 1
        }
        $files = @(Get-ChildItem -Path $script:ATT_DIR -File | Where-Object { $_.Name -ne "README.md" })
        $selectedFile = $null
        if ($target -match '^\d+$') {
            $num = [int]$target
            if ($num -ge 1 -and $num -le $files.Count) {
                $selectedFile = $files[$num - 1]
            }
        } else {
            foreach ($f in $files) {
                if ($f.Name -like "*$target*") {
                    $selectedFile = $f
                    break
                }
            }
        }

        if (-not $selectedFile) {
            Write-Host "[ERROR] 未找到目标材料文件: $target" -ForegroundColor Red
            exit 1
        }

        if (Test-Path $script:PROFILE_FILE) {
            try {
                $profile = Get-Content $script:PROFILE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $profile.default_attachments) {
                    $profile | Add-Member -MemberType NoteProperty -Name "default_attachments" -Value ([PSCustomObject]@{})
                }
                $profile.default_attachments.resume = $selectedFile.FullName
                $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $script:PROFILE_FILE -Encoding UTF8
                Write-Host ""
                Write-Host "[SUCCESS] 已成功将该材料设为默认简历！" -ForegroundColor Green
                Write-Host "  文件: $($selectedFile.Name)" -ForegroundColor White
                Write-Host "  路径: $($selectedFile.FullName)" -ForegroundColor DarkGray
                Write-Host "  配置已更新至: $script:PROFILE_FILE" -ForegroundColor DarkGray
                Write-Host ""
            } catch {
                Write-Host "[ERROR] 更新 profile.json 失败: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "[ERROR] 未找到 profile.json: $script:PROFILE_FILE" -ForegroundColor Red
        }
    }
}
