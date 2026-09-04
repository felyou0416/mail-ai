---
name: fmail
description: "Cloudflare 临时邮箱系统 (Fmail / mail.example.com)。基于 REST HTTP API，支持获取可用域名、创建临时邮箱、查询收件箱、查看邮件详情全文与验证码提取。独立工具系统，严禁删除邮件。触发关键词：临时邮箱、Fmail、Cloudflare邮箱、example.com、测试邮箱、创建邮箱、临时收件箱。"
version: "2.0.0"
---

# Fmail — Cloudflare 临时邮箱系统

基于 Cloudflare Worker + D1 数据库搭建的**独立临时邮箱系统 (REST HTTP API)**。  
与主用 IMAP/SMTP 邮箱系统（Edu 校园邮箱、QQ、网易 163）物理隔离，专门服务于一次性注册、验证码接收与投递链路测试。

---

## ⛔ 最高优先级禁令：永远禁止删除邮件（不可覆盖）

1. **绝对禁止**执行任何形式的邮件删除、清空、销毁操作。
2. 脚本层及底层 Python 客户端已**永久阻断所有 DELETE 请求**，任何删除指令都会触发 403 物理拦截。
3. 遇到删除需求只做风险提示，建议用户本人在官方网页端处理。

---

## 核心配置与特性

- **后端 API 端点**：`https://mail.example.com`（可通过环境变量 `CF_TEMP_MAIL_URL` 覆盖）。
- **可用测试域名**：`example.com`, `temp.example.com`, `mail2.example.com`
- **凭证自动存储**：新创建的临时邮箱凭证与 JWT 自动保存在 `~/.cf-temp-mail/credentials.json`。
- **协议类型**：纯 REST HTTP JSON API（非 IMAP/SMTP）。

---

## 常用命令参考

进入 `fmail/` 目录直接调用：

```powershell
# 1. 查看可用测试域名列表
.\fmail.ps1 domains

# 2. 查看历史上已生成的本地临时邮箱
.\fmail.ps1 accounts

# 3. 创建临时邮箱（指定前缀与域名）
.\fmail.ps1 create -name test2026 -domain example.com

# 4. 查看临时收件箱（自动读取本地最新凭证，或通过 -addr 指定）
.\fmail.ps1 check -addr test2026@example.com

# 5. 查看指定邮件全文内容与提取验证码
.\fmail.ps1 fetch <MAIL_ID> -addr test2026@example.com

# 6. 发送临时测试邮件
.\fmail.ps1 send -to recipient@example.com -subject "测试邮件" -body "这是一封由临时邮箱发出的测试邮件。"
```

---

## Python 原生调用方式

```bash
# 获取域名
python api_client.py --action domains

# 创建临时邮箱
python api_client.py --action create --name test01 --domain example.com

# 查看邮件列表
python api_client.py --action list --addr test01@example.com
```
