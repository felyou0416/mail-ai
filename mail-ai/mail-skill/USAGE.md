# Mail-Skill 本地智能邮件库使用与架构指南

> **所属项目**：`mail-ai` 工具箱  
> **核心定位**：提供邮件本地持久化存储、SQLite FTS5 全文检索、ChromaDB 语义向量搜索、会话线索树溯源、智能摘要与分类归档能力。

---

## 目录
1. [项目结构说明](#1-项目结构说明)
2. [本地存储架构 (`mail_data/`)](#2-本地存储架构-mail_data)
3. [多账户配置与自动桥接机制](#3-多账户配置与自动桥接机制)
4. [统一命令网关与调用方式](#4-统一命令网关与调用方式)
5. [核心功能使用说明](#5-核心功能使用说明)
6. [安全与合规守则](#6-安全与合规守则)

---

## 1. 项目结构说明

```text
mail-skill/
├── SKILL.md                   # AI Agent 技能定义文件
├── README.md                  # 原始项目文档
├── USAGE.md                   # 本指南：整合架构、存储结构与使用手册
├── pyproject.toml             # Python 项目与构建配置
├── requirements.txt           # 核心依赖清单 (imap-tools, beautifulsoup4, chromadb 等)
├── example.config.txt         # 独立运行时的配置模板
├── references/                # 提示词参考与 Jinja2 输出排版模板
│   ├── MEMORY.md
│   └── templates/
│       ├── email_table.md.j2  # 邮件列表 Markdown 模板
│       ├── email_theme.html.j2# 精美 HTML 邮件模板
│       └── thread.md.j2       # 邮件线索树展示模板
├── scripts/
│   ├── mail_cli.py            # CLI 总入口，统一处理命令行参数与格式化输出
│   └── mail_manager/          # 核心业务逻辑实现
│       ├── config_manager.py  # 配置管理器（已支持父级 mail-ai 自动桥接）
│       ├── client.py          # IMAP/POP3 收信与 SMTP 发信客户端
│       ├── db.py              # SQLite (FTS5) + ChromaDB 混合存储引擎
│       ├── classifier.py      # 邮件分类与优先级评估算法
│       ├── query_parser.py    # 自然语言查询解析（时间、发件人、意图提取）
│       ├── detail.py          # 邮件详情 Markdown 高保真渲染器
│       ├── summary_report.py  # 邮件摘要简报与统计报表
│       ├── thread_manager.py  # 会话线索（In-Reply-To / References）线程分析
│       ├── templates.py       # Jinja2 模板管理器
│       ├── email_providers.py # 29+ 常见主流邮箱服务商自动配置字典
│       ├── errors.py          # 统一结构化错误码定义
│       ├── attachment_parser/ # 附件文本与信息解析插件
│       │   ├── pdf_parser.py  # PDF 文本提取
│       │   ├── excel_parser.py# Excel 表格分析
│       │   ├── pptx_parser.py # PPT 幻灯片正文提取
│       │   ├── image_parser.py# 图片 OCR 与尺寸元数据提取
│       │   └── text_parser.py # 纯文本/Markdown 附件提取
│       └── llm/               # 大模型生成接口（AI 回复、高级重分类）
└── tests/                     # 完备的单元测试集
```

---

## 2. 本地存储架构 (`mail_data/`)

为了确保个人数据安全，所有本地生成的数据库与附件均存放在 `mail-skill/mail_data/` 中，且已被根目录 `.gitignore` **全量排除，严禁提交**。

### 目录层级结构

```text
mail_data/
├── tasks/                                 # 异步收取任务进度缓存
│   └── <task_id>.json                     # 存储每个 fetch 任务的状态与进度
└── <account_id>/                          # 按邮箱账户隔离的独立数据沙盒
    ├── mail_index.db                      # SQLite 3 数据库（含 FTS5 全文索引）
    ├── chroma_db/                         # 向量数据库（语义检索持久化数据）
    ├── attachments/                       # 附件存储目录
    │   └── <message_id>/                  # 按邮件全局唯一 ID 隔离的附件
    │       └── 附件文件.pdf
    ├── eml/                               # 原始邮件 EML 归档（可选导出）
    └── json/                              # 结构化 JSON 导出文件（可选导出）
```

### SQLite 核心表结构 (`mail_index.db`)
- `emails`: 存储邮件元数据（Message-ID、UID、发件人、收件人、主题、时间、纯文本正文、HTML 正文、文件夹、重要等级、标签、会话线索 ID 等）。
- `emails_fts`: SQLite FTS5 虚拟表，针对 `subject`、`sender`、`body_text` 建立全文索引，实现毫秒级快速全文匹配。
- `attachments`: 存储附件元数据及解析后的文本提取内容，支持附件内容反查检索。
- `tags` / `email_tags`: 灵活的多标签关联系统。

---

## 3. 多账户配置与自动桥接机制

`mail-skill` 深度整合了 `mail-ai` 的配置体系，具备**两级配置加载与零配置自动桥接**：

1. **自动桥接（推荐，开箱即用）**：
   - 系统会自动扫描父目录 `mail-ai/profiles/` 下的已配置通道（如 `edu`、`qq`、`netease`）。
   - 自动解析对应的 `profile.json` 与 `.env` 中的授权凭据，无需重复手动配置。
2. **独立配置文件**：
   - 也支持在 `mail-skill/` 或项目根目录下创建 `config.txt` 或 `.env`，遵循标准 `MAIL_ACCOUNT_<PREFIX>_*` 规范。
3. **通道别名支持**：
   - 在任何命令中，均可直接使用通道别名（`--account edu`、`--account qq`、`--account netease`），无需手动输入冗长邮箱地址。

---

## 4. 统一命令网关与调用方式

你可以通过顶层网关 `mail.ps1` 直接使用 `mail-skill` 的高级功能，也可通过底层脚本直接调用。

### 方式一：顶层统一入口（最推荐）

| 快捷命令 | 说明 | 示例 |
| :--- | :--- | :--- |
| `.\mail.ps1 sync` | 异步拉取远程邮件并构建本地全文索引与向量库 | `.\mail.ps1 sync --via edu --days 14` |
| `.\mail.ps1 smart-search` | 基于自然语言与语义的智能邮件搜索 | `.\mail.ps1 smart-search "上周导师发送的实验通知"` |
| `.\mail.ps1 summarize` | 自动生成近期邮件的 Markdown 摘要简报 | `.\mail.ps1 summarize --limit 10` |
| `.\mail.ps1 classify` | 评估本地邮件的重要程度与业务分类 | `.\mail.ps1 classify --limit 20` |
| `.\mail.ps1 thread` | 追踪邮件往来回复的时间线索树 | `.\mail.ps1 thread <message_id>` |
| `.\mail.ps1 skill <cmd>` | 透传调用 `mail-skill` 任意原生子命令 | `.\mail.ps1 skill list-providers` |

### 方式二：直接调用 Python CLI

```bash
# 进入 mail-skill 目录
cd E:\Tools\mail-ai\mail-skill

# 查看所有支持的子命令
python scripts/mail_cli.py --help

# 搜索校园邮箱中包含“复试”的邮件
python scripts/mail_cli.py search --account edu "复试"
```

---

## 5. 核心功能使用说明

### 5.1 同步邮件至本地库 (`sync` / `fetch`)
邮件收取采用后台异步任务机制，收取完成后会自动构建 SQLite 关系索引与 FTS5 全文索引：
```powershell
# 拉取校园邮箱最近 7 天的未读邮件
.\mail.ps1 sync --via edu --days 7 --unread-only

# 查看拉取进度
.\mail.ps1 skill fetch-status <task_id>
```

### 5.2 本地全文搜索与语义检索 (`search` / `smart-search`)
- **常规全文搜索**：
  ```powershell
  .\mail.ps1 skill search --account qq "开会"
  ```
- **自然语言语义搜索**：
  支持中文相对时间、人名发件人推断：
  ```powershell
  .\mail.ps1 smart-search "昨天收到的关于夏令营通知"
  ```

### 5.3 邮件线索树追踪 (`thread`)
查看特定邮件及其所有前后回复往来：
```powershell
.\mail.ps1 thread "<message_id>"
```

### 5.4 智能摘要与发件人统计 (`summarize` / `summary-report`)
```powershell
# 汇总最近 20 封邮件的摘要
.\mail.ps1 summarize --limit 20

# 按发件人维度生成聚合报告
.\mail.ps1 skill summary-report --days 7
```

---

## 6. 安全与合规守则

1. ⛔ **禁止删除邮件**：严禁调用任何删除服务端邮件的操作，保护用户邮件资产。
2. 🔒 **敏感数据绝不出库**：
   - 数据库文件、附件、EML 均在 `mail_data/` 内部管理，并已被 `.gitignore` 保护。
   - 所有密码与授权码仅在内存中通过环境变量或本地 `.env` 隔离读取，严禁在日志或代码中打印明文。
3. 🛡️ **优雅降级原则**：
   - 若系统未安装 `chromadb` 等重量级 AI 依赖，系统会自动降级为 SQLite FTS5 关键词检索，核心邮件收发与阅读功能 100% 正常运行。
