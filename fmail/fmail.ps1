<#
.SYNOPSIS
  Cloudflare 临时邮箱系统命令行交互脚本 (Fmail)
.DESCRIPTION
  为 Cloudflare 临时邮箱 (https://mail.example.com) 提供统一的 PowerShell 交互界面。
  底层调用同目录下的 api_client.py。

  常用命令：
    .\fmail.ps1 domains                                      # 查看可用域名列表
    .\fmail.ps1 accounts                                     # 查看本地保存的临时邮箱
    .\fmail.ps1 create -name test -domain example.com       # 创建新临时邮箱
    .\fmail.ps1 check [-addr user@example.com]              # 查看收件箱
    .\fmail.ps1 fetch <ID> [-addr user@example.com]         # 查看邮件全文详情
    .\fmail.ps1 send -to x@y.com -subject 主题 -body 正文     # 发送临时测试邮件

.NOTES
  安全红线：永久物理禁止邮件删除
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:PY_CLIENT = Join-Path $script:SCRIPT_DIR "api_client.py"

function Show-Help {
    Write-Host ""
    Write-Host "  Fmail — Cloudflare 临时邮箱系统" -ForegroundColor Cyan
    Write-Host "  后端 API: https://mail.example.com" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  使用方式: .\fmail.ps1 <command> [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "  常用命令:" -ForegroundColor White
    Write-Host "    domains               获取可用域名列表"
    Write-Host "    accounts              查看本地保存的临时邮箱"
    Write-Host "    create                创建临时邮箱 (-name <前缀> -domain <域名>)"
    Write-Host "    check / list          查看收件箱 (-addr <邮箱地址> -limit 20)"
    Write-Host "    fetch <ID>            查看邮件完整内容与验证码 (-id <ID> -addr <邮箱>)"
    Write-Host "    send                  发送测试邮件 (-to <收件人> -subject <主题> -body <正文>)"
    Write-Host "    admin-addresses       管理员查询全部地址 (-admin-password <密码>)"
    Write-Host "    admin-mails           管理员查询全站邮件 (-admin-password <密码>)"
    Write-Host ""
}

$allArgs = @($args)
if ($allArgs.Count -eq 0) { Show-Help; exit 0 }

# ⛔ 防火墙：物理拦截删除请求
$dangerKeywords = @("delete", "remove", "purge", "trash", "expunge", "destroy")
foreach ($token in $allArgs) {
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

$cmd = [string]$allArgs[0]
$cmd = $cmd.ToLower()
$restArgs = if ($allArgs.Count -gt 1) { @($allArgs | Select-Object -Skip 1) } else { @() }

$pyArgs = @()

switch ($cmd) {
    "domains" {
        $pyArgs = @("--action", "domains")
    }

    "accounts" {
        $pyArgs = @("--action", "accounts")
    }

    "create" {
        $pyArgs = @("--action", "create")
        $i = 0
        while ($i -lt $restArgs.Count) {
            if ($restArgs[$i] -in @("-name", "--name") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--name", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-domain", "--domain") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--domain", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-no-save", "--no-save")) {
                $pyArgs += @("--no-save")
            }
            $i++
        }
    }

    { $_ -in @("check", "list") } {
        $pyArgs = @("--action", "list")
        $i = 0
        while ($i -lt $restArgs.Count) {
            if ($restArgs[$i] -in @("-addr", "--addr") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--addr", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-jwt", "--jwt") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--jwt", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-limit", "--limit") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--limit", $restArgs[++$i])
            }
            $i++
        }
    }

    "fetch" {
        $pyArgs = @("--action", "fetch")
        $i = 0
        if ($restArgs.Count -gt 0 -and $restArgs[0] -match '^\d+$') {
            $pyArgs += @("--mail-id", $restArgs[0])
            $i = 1
        }
        while ($i -lt $restArgs.Count) {
            if ($restArgs[$i] -in @("-id", "--mail-id", "--id") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--mail-id", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-addr", "--addr") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--addr", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-jwt", "--jwt") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--jwt", $restArgs[++$i])
            }
            $i++
        }
    }

    "send" {
        $pyArgs = @("--action", "send")
        $i = 0
        while ($i -lt $restArgs.Count) {
            if ($restArgs[$i] -in @("-to", "--to") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--to", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-subject", "--subject") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--subject", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-body", "--body", "-content", "--content") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--content", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-addr", "--addr") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--addr", $restArgs[++$i])
            } elseif ($restArgs[$i] -in @("-jwt", "--jwt") -and $i + 1 -lt $restArgs.Count) {
                $pyArgs += @("--jwt", $restArgs[++$i])
            }
            $i++
        }
    }

    "admin-addresses" {
        $pyArgs = @("--action", "admin-addresses") + $restArgs
    }

    "admin-mails" {
        $pyArgs = @("--action", "admin-mails") + $restArgs
    }

    default {
        $pyArgs = @("--action", $cmd) + $restArgs
    }
}

python $script:PY_CLIENT @pyArgs
exit $LASTEXITCODE
