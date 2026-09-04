﻿---
name: mail-service
description: "主用邮件服务基础设施技能。支持 高校校园邮箱 (Edu Mail) (@*.edu.cn)、QQ 邮箱 (@qq.com)、网易 163 邮箱 (@163.com)。基于标准 IMAP/SMTP 协议，提供严格的环境变量隔离、数据资产隔离与底层共享驱动，永远禁止删除邮件。发信必须显式指定通道。触发词：邮件、查邮件、收件箱、发信、mail、campus、qq、163。"
version: "2.1.0"
---

# 主用邮件服务基础设施技能 (Mail Service)

本技能管理所有真实个人与学术主用邮箱，涵盖 **高校校园邮箱 (Edu Mail)**、**QQ 邮箱** 与 **网易 163 邮箱**。基于标准 IMAP/SMTP 协议，采用**底层共享引擎 + Profile/Reference 严格隔离架构**，彻底消除代码冗余，同时严格保障各邮箱之间的环境独立性与数据资产安全。

> 💡 **注**：临时测试邮箱系统（Cloudflare 临时邮箱）已完全独立至 `fmail/` 目录；高校推免业务已独立至 `套磁信/` 目录。

---

## ⛔ 最高安全红线与发信原则

### 1. 永远禁止删除邮件（物理阻断，不可覆盖）
* **绝对禁止**执行任何形式的邮件删除、清空、销毁操作（包括单封/批量/整箱删除）。
* 核心引擎在入口处设置了物理防火墙，任何包含 `delete`、`remove`、`purge`、`trash` 等关键词的操作将直接被拦截退出（HTTP 403 级别阻断）。
* 若用户有邮件清理需求，请明确告知风险，并引导用户**登录官方网页端手动处理**。

### 2. 发信通道强制显式确认（禁止静默猜测）
* 发送邮件时，必须通过 `--via <edu|qq|netease>`（或进入具体邮件系统）明确发信通道。
* **如果主人未明确指出使用哪个邮箱发信，AI 必须立即停下来向主人提问确认，严禁擅自猜测或自动兜底！**

---

## 核心隔离架构设计

```
mail-service/
├── SKILL.md                    # 本文档：统一规范与命令说明
├── qq.ps1                      # QQ 邮箱专属快捷入口 (.\qq.ps1)
├── netease.ps1                 # 网易 163 邮箱专属快捷入口 (.\netease.ps1)
├── assets\app-icon.png         # 技能图标
│
├── core/                       # 【唯一共享底层引擎】
│   ├── mail-engine.ps1         # 统一调度器（参数解析、环境隔离、重试、附件自愈）
│   ├── imap.bundle.js          # 单份 IMAP 收信驱动（Node.js）
│   ├── smtp.bundle.js          # 单份 SMTP 发信驱动（Node.js）
│   └── setup-credential.ps1    # 通用 DPAPI 加密凭据配置脚本
│
├── profiles/                   # 【3 大邮箱专属资产与配置隔离】
│   ├── edu/                    # 高校校园邮箱 (Edu Mail) (.env, contacts.json, signature.html, downloads/, mail.log)
│   ├── qq/                     # QQ 邮箱 (.env, signature.html, downloads/, mail.log)
│   └── netease/                # 网易 163 邮箱 (.credential, .env, signature.html, downloads/, mail.log)
│
└── references/                 # 【各邮箱专属差异参考手册】
    ├── edu.md                 # 高校校园网特征、网易企业邮配置、导师联系人、禁发临时域规则
    ├── qq.md                   # QQ 邮箱授权码规范、发件人一致性要求
    └── netease.md              # 网易 163 邮箱 DPAPI 配置、反垃圾 554 防御建议
```

### 关键隔离机制：
1. **环境变量清理与隔离**：每次调用前清理所有相关的进程环境变量，执行后自动还原，杜绝 Edu 校园邮箱与 163 在共享 Node bundle 时的串号风险。
2. **数据与资产隔离**：
   - **签名**：各自独立加载 `signature.html`。
   - **通讯录**：Edu 校园邮箱拥有专有的学术通讯录 `contacts.json`，支持别名发信。
   - **附件下载**：各邮箱附件严格下载至各自 profile 的 `downloads/` 目录，防止混杂。
   - **审计日志**：各邮箱独立输出至各自 profile 的 `mail.log`。

---

## 命令行接口 (CLI)

### 1. 快捷入口方式（推荐，进入 mail-service 后使用）

```powershell
# 高校校园邮箱 (Edu Mail)
.\edu.ps1 test
.\edu.ps1 check --limit 5
.\edu.ps1 search --query "面试"
.\edu.ps1 send --to "prof@university.edu.cn" --subject "课题汇报" --body "王老师您好..."

# QQ 邮箱
.\qq.ps1 test
.\qq.ps1 check --limit 5
.\qq.ps1 send --to "friend@example.com" --subject "问候" --body "你好！"

# 网易 163 邮箱
.\netease.ps1 test
.\netease.ps1 check --limit 5
.\netease.ps1 send --to "hr@company.com" --subject "应聘材料" --body "您好，附件为简历。" --attach "resume.pdf"
```

### 2. 核心调度器调用格式

```powershell
powershell -ExecutionPolicy Bypass -File .\core\mail-engine.ps1 -Account <edu|qq|netease> <command> [options]
```

| 操作 | 命令 | 说明与关键参数 |
| :--- | :--- | :--- |
| **连接测试** | `test` | 测试 IMAP 收信与 SMTP 发信连接 |
| **查看收件箱** | `check` | 查看最新邮件列表（`--limit 10`） |
| **搜索邮件** | `search` | `--query "关键词"` / `--from "发件人"` / `--subject "主题"` |
| **查看邮件全文** | `fetch <UID>` | 获取邮件正文、发件人、收件人、附件列表 |
| **下载附件** | `download <UID>` | 默认下载至 `profiles/<account>/downloads/` |
| **发送邮件** | `send` | 必填 `--to` 和 `--subject`。支持 `--body`、`--attach`、`--html`、`--no-sig`、`--draft`、`--schedule "时间"` |
| **标记已读/未读** | `mark-read <UID>` / `mark-unread <UID>` | 变更邮件状态（非破坏性操作） |
| **文件夹列表** | `list-mailboxes` | 列出所有邮件文件夹 |
| **草稿箱管家** | `draft` | 支持 `list`（列表）、`view <ID>`（详情）、`clean-test`（清理测试）、`send <ID> --confirm`（外发） |
| **全邮箱巡检** | `scan` | 一键检查收件箱、草稿箱、垃圾邮件、广告邮件等文件夹健康状态 |
| **全箱深搜** | `search-all <词>` | 跨所有文件夹（含垃圾箱与广告箱）深度检索 |
| **系统体检中心** | `doctor` | 一键全通道连通性、材料库规范、草稿追踪、垃圾箱误拦截诊断 |
| **导师风控查重** | `check-mentor <导师> [单位]` | 14天投递查重与同实验室/同单位冲突预警 |
