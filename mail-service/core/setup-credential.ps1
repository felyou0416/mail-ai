<#
.SYNOPSIS
  使用 Windows DPAPI 加密存储指定邮箱的授权码
.DESCRIPTION
  支持对高校校园邮箱 (Edu)、QQ、网易 163 邮箱的授权码进行 DPAPI 高强度加密。
  加密后的 .credential 文件保存在对应的 profiles/<account>/ 目录下，仅当前 Windows 用户可解密。
.PARAMETER Profile
  目标邮箱配置文件名称 (edu, qq, netease)
.EXAMPLE
  .\setup-credential.ps1 -Profile netease
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("edu", "qq", "netease")]
    [string]$Profile
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$profilesDir = Join-Path (Split-Path -Parent $coreDir) "profiles"
$targetProfileDir = Join-Path $profilesDir $Profile

if (-not (Test-Path $targetProfileDir)) {
    Write-Host "[ERROR] 未找到 Profile 目录: $targetProfileDir" -ForegroundColor Red
    exit 1
}

$profileConfigPath = Join-Path $targetProfileDir "profile.json"
$displayName = $Profile
$email = ""
if (Test-Path $profileConfigPath) {
    $cfg = Get-Content $profileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $displayName = $cfg.displayName
    $email = $cfg.email
}

$credFile = Join-Path $targetProfileDir ".credential"

if (Test-Path $credFile) {
    $overwrite = Read-Host "已存在加密凭证 ($Profile)，是否覆盖？(y/N)"
    if ($overwrite -ne "y") {
        Write-Host "已取消。" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "=== 配置 $displayName 授权码加密凭据（DPAPI）===" -ForegroundColor Cyan
Write-Host "账号: $email" -ForegroundColor DarkGray
Write-Host "授权码将通过 Windows DPAPI 加密，仅当前机器与用户可解密。" -ForegroundColor DarkGray
Write-Host ""

$mailPass = Read-Host "请输入 $displayName 授权码（输入不可见）" -AsSecureString
if (-not $mailPass) {
    Write-Host "[ERROR] 未输入授权码！" -ForegroundColor Red
    exit 1
}

$credObj = [PSCustomObject]@{
    Account = $Profile
    Email   = $email
    Pass    = $mailPass | ConvertFrom-SecureString
}

$credObj | ConvertTo-Json | Set-Content $credFile -Encoding UTF8

# 设置 ACL 权限保护，仅当前用户完全控制
$acl = Get-Acl $credFile
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    "FullControl",
    "Allow"
)
$acl.AddAccessRule($rule)
Set-Acl $credFile $acl

Write-Host ""
Write-Host "[SUCCESS] 授权码已安全加密保存到: $credFile" -ForegroundColor Green
