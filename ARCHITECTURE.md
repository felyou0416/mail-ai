# Mail-AI 项目架构文档

> 本文档是对 [README.md](./README.md) 的技术补充，覆盖完整的项目架构、模块职责、数据流、安全模型与开发指南。
> 最后更新：2026-09-05（目录重构 + mail-skill 整合完成后）

---

## 一、项目概览

Mail-AI 是一套自包含的本地邮件自动化工具箱，专为 AI Agent 与本地大模型设计。项目由三大模块组成，通过顶层统一网关 `mail.ps1` 调度，实现收发邮件、智能检索、推免套磁、Web 可视化等全流程能力。

| 模块 | 目录 | 定位 | 技术栈 |
|------|------|------|--------|
| 核心邮件引擎 | `mail-ai/` | 三大真实邮箱 (Edu/QQ/NetEase) 收发 + AI 智能检索 + Web 控制台 | PowerShell + Node.js + Python |
| 临时邮箱 | `fmail/` | Cloudflare 一次性邮箱，验证码与链路测试 | Python REST API |
| 推免套磁 | `taoci/` | 导师联系全流程 SOP（草稿生成、批量发送、回复跟踪、导师查重） | PowerShell |

---

## 二、目录结构详解

```
mail-ai\                             # 项目根目录
├── mail.ps1                          # 顶层统一网关（发信/收信/AI检索/体检/套磁调度）
├── ui.ps1                            # Web 控制台启动器
├── setup-local.ps1                   # 本地环境初始化向导
├── .gitignore                        # 全局敏感文件排除
├── README.md                         # 项目说明文档
├── ARCHITECTURE.md                   # 本文档（技术架构）
├── INTEGRATION_PLAN.md               # mail-skill 整合方案
├── project_memory.md                 # 项目记忆与使用准则
│
├── fmail\                            # ① Cloudflare 临时邮箱
│   ├── SKILL.md                      #   技能说明与 API 规范
│   ├── fmail.ps1                     #   CLI 交互入口
│   └── api_client.py                 #   REST API 客户端（防删防火墙）
│
├── mail-ai\                          # ② 核心邮件引擎 + AI 检索
│   ├── SKILL.md                      #   统一技能主文档
│   ├── edu.ps1                       #   Edu 邮箱快捷入口
│   ├── qq.ps1                        #   QQ 邮箱快捷入口
│   ├── netease.ps1                   #   NetEase 邮箱快捷入口
│   │
│   ├── core\                         #   共享底层引擎（单点维护）
│   │   ├── mail-engine.ps1           #   核心调度（参数解析、环境隔离、重试、智能搜索）
│   │   ├── imap.bundle.js            #   IMAP 收信驱动 (Node.js)
│   │   ├── smtp.bundle.js            #   SMTP 发信驱动 (Node.js)
│   │   ├── draft-manager.ps1         #   草稿箱管理
│   │   ├── mailbox-inspector.ps1     #   全邮箱巡检与深搜
│   │   ├── system-doctor.ps1         #   系统体检诊断
│   │   └── setup-credential.ps1      #   DPAPI 加密凭据配置
│   │
│   ├── profiles\                     #   账户资产隔离
│   │   ├── edu\                      #   Edu 邮箱 (.env, contacts.json, signature.html, ...)
│   │   ├── qq\                       #   QQ 邮箱 (.env, signature.html, ...)
│   │   └── netease\                  #   NetEase 邮箱 (.credential, .env, signature.html, ...)
│   │
│   ├── references\                   #   各邮箱差异手册
│   │   ├── edu.md
│   │   ├── qq.md
│   │   └── netease.md
│   │
│   ├── mail-skill\                   #   AI 智能检索引擎
│   │   ├── SKILL.md                  #   技能说明
│   │   ├── USAGE.md                  #   架构与使用指南
│   │   ├── scripts\
│   │   │   ├── mail_cli.py           #   CLI 入口（Windows UTF-8 自动适配）
│   │   │   └── mail_manager\         #   核心模块
│   │   │       ├── config_manager.py #   配置管理（自动桥接 profiles/）
│   │   │       ├── db.py             #   SQLite FTS5 全文索引
│   │   │       ├── client.py         #   IMAP 收取客户端
│   │   │       ├── classifier.py     #   AI 邮件分类
│   │   │       ├── summary_report.py #   摘要报告生成
│   │   │       ├── thread_manager.py #   会话线索管理
│   │   │       ├── reply_assistant.py#   回复助手
│   │   │       ├── llm\              #   LLM 客户端与提示词
│   │   │       └── attachment_parser\#   附件解析 (PDF/Excel/PPT/图片)
│   │   └── mail_data\                #   运行时数据（gitignore 排除）
│   │       └── <account_id>/         #   按账户隔离
│   │           ├── mail_index.db     #   SQLite 数据库
│   │           ├── chroma_db/        #   向量索引
│   │           ├── attachments/      #   附件缓存
│   │           ├── eml/              #   EML 归档
│   │           └── json/             #   导出数据
│   │
│   └── web\                          #   Web 控制台（前后端分离）
│       ├── server.py                 #   Python REST API 服务
│       └── index.html                #   HTML5 + TailwindCSS SPA
│
└── taoci\                            # ③ 推免套磁信系统
    ├── SKILL.md                      #   业务流程与 SOP 规约
    ├── 套磁信模板.md                  #   4 套模板 + 风格分析
    ├── core\
    │   ├── engine\                   #   核心引擎
    │   │   ├── batch-send.ps1        #   批量发送（CSV + 模板引擎）
    │   │   ├── create-draft.ps1      #   草稿生成
    │   │   ├── track-mail.ps1        #   回复跟踪与催信预警
    │   │   ├── mentor-checker.ps1    #   导师风控查重
    │   │   ├── attachment-manager.ps1#   附件材料库管理
    │   │   └── tracking-helper.ps1  #   跟踪辅助函数
    │   ├── schemas\                  #   数据模型
    │   └── templates\                #   模板库
    ├── personal\                     #   个人数据（gitignore 排除）
    │   ├── profile.json              #   学生画像
    │   ├── contacts.csv              #   导师通讯录
    │   ├── tracking.csv              #   投递记录
    │   ├── attachments\              #   简历/陈述/申请材料
    │   ├── drafts\                   #   草稿归档
    │   ├── sent\                     #   已发送归档
    │   └── references\              #   个人科研复盘
    └── scripts\                      #   辅助脚本
```

---

## 三、模块职责与数据流

### 3.1 顶层网关 (`mail.ps1`)

所有用户操作的统一入口，负责命令路由、通道选择与子模块调度。

```
用户命令                    mail.ps1 路由
─────────────────────────────────────────────────────
mail.ps1 send --via edu  → mail-ai/core/mail-engine.ps1 → smtp.bundle.js
mail.ps1 check --via qq  → mail-ai/core/mail-engine.ps1 → imap.bundle.js
mail.ps1 smart-search    → mail-ai/mail-skill/scripts/mail_cli.py
mail.ps1 doctor          → mail-ai/core/system-doctor.ps1
mail.ps1 draft list      → mail-ai/core/draft-manager.ps1
mail.ps1 batch-send      → taoci/core/engine/batch-send.ps1 → mail-engine.ps1
mail.ps1 ui              → mail-ai/web/server.py
mail.ps1 fmail ...       → fmail/fmail.ps1 → api_client.py
```

### 3.2 核心邮件引擎 (`mail-ai/core/`)

| 脚本 | 职责 | 关键特性 |
|------|------|---------|
| `mail-engine.ps1` | 参数解析、环境隔离、命令调度 | 进程级环境变量注入与即时清空；MIME 解码智能搜索（GB2312 兼容） |
| `imap.bundle.js` | IMAP 收信驱动 | 支持 SSL/TLS、附件下载、文件夹列表、标记已读/未读 |
| `smtp.bundle.js` | SMTP 发信驱动 | 支持 SSL/TLS、HTML 邮件、多附件、定时发送 |
| `draft-manager.ps1` | 草稿箱全生命周期 | list/view/send/clean-test，JSON 格式存储 |
| `mailbox-inspector.ps1` | 全邮箱健康巡检 | 跨文件夹（含垃圾箱/广告箱）深度搜索 |
| `system-doctor.ps1` | 系统全局体检 | 4 邮箱通道 + mail-skill 依赖 + 附件规范 + 草稿追踪 |
| `setup-credential.ps1` | DPAPI 加密凭据 | Windows 原生加密，仅当前用户可解密 |

### 3.3 AI 智能检索引擎 (`mail-ai/mail-skill/`)

分层依赖架构，优雅降级：

```
Layer 2 (高阶语义)  ← chromadb + sentence-transformers
    ↓ 未安装则降级
Layer 1 (标准检索)  ← imap-tools + beautifulsoup4
    ↓ 未安装则降级
Layer 0 (基础运行)  ← 零 pip 依赖，原有功能 100% 正常
```

| 命令 | 功能 | 数据存储 |
|------|------|---------|
| `sync` | 增量收取邮件并建本地索引 | SQLite FTS5 + ChromaDB |
| `smart-search` | 自然语言语义搜索 | 向量相似度匹配 |
| `summarize` | 邮件分类摘要报告 | Markdown 输出 |
| `classify` | 邮件重要度评估 | critical/high/normal/low |
| `thread` | 会话线索树 | 基于 References 头域 |

**账户桥接机制**：`config_manager.py` 自动发现 `mail-ai/profiles/` 下已配置的账户，无需手动维护 `config.txt`。

### 3.4 推免套磁系统 (`taoci/`)

9 步标准作业程序 (SOP)：

```
1. 确认专业方向 → 2. 检索推免通知 → 3. 挖掘候选导师
→ 4. 匹配评估推荐 → 5. 对话选定导师 → 6. 草稿深度定制
→ 7. 确认发信通道 → 8. 附件合规预检 → 9. 默认存入草稿箱
```

双层隔离架构：
- `core/` — 通用底座（可开源）：引擎脚本、模板、Schema
- `personal/` — 个人私密（gitignore 排除）：画像、通讯录、投递记录、附件、草稿

### 3.5 Web 控制台 (`mail-ai/web/`)

前后端分离，零第三方依赖：

| 层 | 技术 | 文件 |
|----|------|------|
| 前端 | HTML5 + TailwindCSS (CDN) | `index.html` (24KB SPA) |
| 后端 | Python 标准库 `http.server` | `server.py` (7KB) |
| 通信 | JSON REST API | 7 个端点 |

---

## 四、安全模型

### 4.1 凭证安全

| 邮箱 | 凭证类型 | 存储方式 | gitignore |
|------|---------|---------|-----------|
| Edu (WHUT) | 授权码 | `.env` 文件 | ✅ 排除 |
| QQ | 授权码 | `.env` 文件 | ✅ 排除 |
| NetEase (163) | 授权码 | Windows DPAPI 加密 | ✅ 排除 |
| Fmail | JWT Token | `credentials.json` | ✅ 排除 |

**凭证读取优先级**：连接器环境变量 > DPAPI 加密 > `.env` 文件 > 系统环境变量

### 4.2 数据隔离

| 数据类型 | 存储位置 | 隔离方式 |
|---------|---------|---------|
| 邮件附件下载 | `profiles/<account>/downloads/` | 按账户物理隔离 |
| 草稿 | `profiles/<account>/drafts/` | 按账户隔离 |
| mail-skill 索引 | `mail-skill/mail_data/<account_id>/` | 按账户隔离（SQLite + ChromaDB） |
| 套磁个人数据 | `taoci/personal/` | 与开源代码物理隔离 |
| 审计日志 | `profiles/<account>/mail.log` | 按账户独立记录 |

### 4.3 物理防删

- 所有 `.ps1` 和 `.py` 脚本代码层面一票否决删除指令
- Fmail API 客户端永久屏蔽 DELETE 端点
- 遇到删除需求只做风险提示，建议用户登录官方网页端处理

### 4.4 .gitignore 全量排除规则

```
# 凭证
.env / .credential / *.env

# 运行时数据
mail.log / downloads/ / drafts/ / .preview/

# 个人通讯录
contacts.json / **/contacts.json

# mail-skill 运行时
mail-ai/mail-skill/mail_data/
mail-ai/mail-skill/config.txt
mail-ai/mail-skill/**/__pycache__/

# 套磁个人数据
taoci/personal/

# Profile 真实配置
mail-ai/profiles/**/profile.json
mail-ai/profiles/**/signature.html
```

---

## 五、功能特性清单

### 核心邮件功能 (12 项)

| # | 功能 | 命令 | 说明 |
|---|------|------|------|
| 1 | 附件自动复制 | `send --attach` | 非白名单目录附件自动复制到 Downloads |
| 2 | 批量套磁发送 | `batch-send` | CSV 驱动 + 4 模板 + 随机间隔 |
| 3 | 套磁跟踪 | `track --needs-followup` | 回复检测 + 7 天提醒 |
| 4 | 统一入口 | `mail.ps1` | 自动路由通道（felyou.cc.cd → QQ） |
| 5 | HTML 签名 | `send`（自动追加） | `--no-sig` 跳过 |
| 6 | 草稿保存 | `send --draft` | 保存到 drafts/ 目录 |
| 7 | 定时发送 | `send --schedule "时间"` | Windows 任务计划一次性任务 |
| 8 | 通讯录 | `send --to "于乐谦"` | contacts.json 别名解析 |
| 9 | 错误重试 | `Invoke-WithRetry` | 3 次重试，5/10/15 秒间隔 |
| 10 | 日志记录 | `Write-ProfileLog` | 所有操作写入 mail.log |
| 11 | 邮件统计 | `stats` | 本月收发数量、未读数 |
| 12 | 附件白名单 | `$allowedDirs` | 可自定义扩展 |

### AI 智能功能 (6 项)

| # | 功能 | 命令 | 依赖层 |
|---|------|------|--------|
| 13 | 本地索引同步 | `sync --via edu --days 14` | Layer 1+ |
| 14 | 语义搜索 | `smart-search "自然语言"` | Layer 2 |
| 15 | 邮件摘要 | `summarize --limit 10` | Layer 1+ |
| 16 | 邮件分类 | `classify <id>` | Layer 1+ |
| 17 | 会话线索 | `thread <id>` | Layer 0 |
| 18 | 智能搜索(GB2312) | `search "关键词"` | Layer 0（内置 MIME 解码） |

---

## 六、开发指南

### 6.1 新增邮箱通道

1. 在 `mail-ai/profiles/` 下创建新目录（如 `outlook/`）
2. 从 `profile.sample.json` 复制并填入服务器配置
3. 运行 `setup-credential.ps1 -Profile outlook` 配置凭据
4. 创建 `mail-ai/outlook.ps1` 快捷入口（参照 `edu.ps1`）
5. 在 `references/` 下创建 `outlook.md` 差异手册

### 6.2 新增套磁模板

1. 在 `taoci/core/templates/` 下创建模板文件
2. 在 `batch-send.ps1` 的模板映射中注册
3. 在 `套磁信模板.md` 中补充说明

### 6.3 扩展 Web API

1. 在 `mail-ai/web/server.py` 中新增路由处理函数
2. 在 `mail-ai/web/index.html` 中添加前端卡片
3. 在 README.md 的 API 表格中补充文档

### 6.4 提交前检查

```powershell
# 1. 确认无敏感文件被暂存
git status

# 2. 运行系统体检
.\mail.ps1 doctor

# 3. 确认 .gitignore 生效
git diff --cached --name-only | Select-String ".env|.credential|contacts.json|mail_data|personal/"
# 应输出为空
```

---

## 七、模块版本

| 模块 | 版本 | 文档 |
|------|------|------|
| mail-ai (核心引擎) | v2.1.0 | `mail-ai/SKILL.md` |
| taoci (推免套磁) | v3.3.0 | `taoci/SKILL.md` |
| fmail (临时邮箱) | v2.0.0 | `fmail/SKILL.md` |
| mail-skill (AI 检索) | — | `mail-ai/mail-skill/SKILL.md` |
| Web 控制台 | — | `mail-ai/web/` |
