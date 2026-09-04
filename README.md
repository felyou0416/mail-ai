# Mail-AI 智能邮件自动化工具箱

> 本项目是一套专为 **本地大模型 / AI Agent (Antigravity & Trae)** 打造的自包含高可用邮件技能矩阵。  
> 采用 **统一共享底层核心引擎 + 专属 Profile/References 深度隔离架构**，彻底消除代码冗余，同时严格保障各邮件系统之间的环境独立性与数据资产安全。

---

## 💡 使用模式与核心准则（重要）

1. **深入邮件系统（标准工作流 · 推荐）**：
   * **除非只是快速发一封邮件，一般建议进入具体的邮件系统子目录**，查阅该系统的专属 `SKILL.md`，使用该系统的专属封装脚本进行收发与配置。
   * 每个邮件系统自包含专属凭证、配置、个性化签名、通讯录及专属下载目录。
2. **顶层入口仅用于快速发信与多通道调度 (`mail.ps1`)**：
   * 根目录下的 `mail.ps1` 定位为**快速发邮件**与统一状态巡检。
   * **发信通道强制显式确认**：发信时必须显式指定 `--via edu`、`--via qq` 或 `--via netease`。若用户未明确指定发信邮箱，**AI 必须主动停下来向用户确认，严禁擅自猜测代发**。
3. **⛔ 绝对禁止删除任何邮件（最高安全禁令 · 物理阻断）**：
   * 无论何种理由（声称测试、已授权、已备份），全套工具代码层永久物理阻断删除端点，严禁执行删除/清空/销毁操作。
4. **严格的环境与数据隔离**：
   * 核心调度器在每次调用前自动彻底清空进程级邮件环境变量，调用后清理，杜绝凭据与配置串号交叉污染。

---

## 整体架构与目录设计

```
mail-ai\
├── mail.ps1                        # 顶层快速发信与多通道网关（必须显式 --via）
├── README.md                       # 本文档（工具箱全局索引与规范）
├── project_memory.md               # 核心项目记忆与使用准则
│
│  ================ 【1. 真实主用邮箱基础设施 (IMAP/SMTP)】 ================
│
├── mail-service\                   # 【真实主邮箱矩阵（高校校园邮箱 Edu、QQ、网易 163）】
│   ├── SKILL.md                    # 统一技能主文档（全局规范、所有命令语法、最高防删红线）
│   ├── edu.ps1                    # 高校校园邮箱 (Edu Mail)专属快捷入口 (.\edu.ps1)
│   ├── qq.ps1                      # QQ 邮箱专属快捷入口 (.\qq.ps1)
│   ├── netease.ps1                 # 网易 163 邮箱专属快捷入口 (.\netease.ps1)
│   ├── assets\app-icon.png         # 技能图标
│   │
│   ├── core\                       # 【唯一共享底层引擎（单点维护，杜绝冗余）】
│   │   ├── mail-engine.ps1         # 核心调度脚本（参数解析、环境隔离、重试、附件自愈）
│   │   ├── imap.bundle.js          # 单份 IMAP 收信驱动（Node.js）
│   │   ├── smtp.bundle.js          # 单份 SMTP 发信驱动（Node.js）
│   │   └── setup-credential.ps1    # 通用 DPAPI 加密凭据配置脚本
│   │
│   ├── profiles\                   # 【3 大邮箱专属资产与配置隔离】
│   │   ├── edu\                   # 高校校园邮箱 (.env, contacts.json, signature.html, downloads/, mail.log)
│   │   ├── qq\                     # QQ 邮箱 (.env, signature.html, downloads/, mail.log)
│   │   └── netease\                # 网易 163 邮箱 (.credential, .env, signature.html, downloads/, mail.log)
│   │
│   └── references\                 # 【各邮箱专属差异参考手册 (References)】
│       ├── edu.md                 # 高校校园网特征、邮件底座配置、导师联系人、禁发临时域规则
│       ├── qq.md                   # QQ 邮箱授权码规范、发件人一致性要求
│       └── netease.md              # 网易 163 邮箱 DPAPI 配置、反垃圾 554 防御建议
│
│  ================ 【2. 独立临时测试邮箱工具 (REST HTTP API)】 ================
│
├── fmail\                          # 【Cloudflare 临时邮箱系统 (Fmail)】
│   ├── SKILL.md                    # 临时邮箱专属技能说明与 API 规范
│   ├── fmail.ps1                   # 专属命令行交互入口（.\fmail.ps1）
│   └── api_client.py               # 核心 Python REST 客户端（防删防火墙、验证码提取）
│
│  ================ 【3. 专项业务 Skill（推免学术联系）】 ================
│
└── 套磁信\                         # 【高校推免 / 保研导师联系专项业务】
    ├── SKILL.md                    # 专属业务流程与 Agent 动作规约
    ├── 套磁信模板.md                # 4 套专属模板库 + 风格分析 + 历史统计
    ├── contacts.sample.csv         # 导师通讯录标准导入样例
    ├── tracking.csv                # 发送历史与状态记录
    └── scripts\
        ├── batch-send.ps1          # 批量个性化生成与防封发送引擎（直连 mail-engine）
        └── track-mail.ps1          # 回复检索与 7 天未回复催信预警（直连 mail-engine）
```

---

## 4 大邮件系统隔离特性对比

| 维度 | 高校校园邮箱 (Edu Mail) | QQ 邮箱 | 网易 163 邮箱 | Cloudflare 临时邮箱 (Fmail) |
| :--- | :--- | :--- | :--- | :--- |
| **账号地址** | `<学号/工号>@your_school.edu.cn` | `<QQ号>@qq.com` | `<用户名>@163.com` | 动态生成（3个可用测试域） |
| **核心定位** | 校园学术、导师沟通、科研课题 | 个人日常、生活通知、外部注册 | 商务沟通、求职招聘、工作往来 | 一次性验证码、链路测试、防垃圾注册 |
| **驱动协议** | IMAP / SMTP (网易企业邮底座) | IMAP / SMTP (腾讯标准节点) | IMAP / SMTP (网易 163 节点) | **REST HTTP API** (Python 客户端) |
| **凭证机制** | 客户端专用授权码 | 16 位英文授权码 | **Windows DPAPI 加密凭据** | JWT Token / 本地 credentials.json |
| **专属签名** | 高校规范学术签名 | 个人生活简约签名 | 商务联络正式签名 | 无签名 |
| **风控隔离** | **严禁向外部临时域发信** | 严格绑定发件人一致性 | **防 554 垃圾拦截（限频/防空正文）** | **物理屏蔽所有删除接口** |
| **附件隔离** | `profiles/edu/downloads/` | `profiles/qq/downloads/` | `profiles/netease/downloads/` | `profiles/fmail/downloads/` |

---

## 快速上手与常用命令

### 1. 全局连通性测试
```powershell
# 测试所有 4 个邮箱通道
.\mail.ps1 test
```

### 2. 快速收信（顶层入口）
```powershell
# 查看高校校园邮箱收件箱（默认通道）
.\mail.ps1 check --limit 5

# 查看网易 163 邮箱收件箱
.\mail.ps1 check --via netease --limit 5

# 查看 QQ 邮箱收件箱
.\mail.ps1 check --via qq --limit 5
```

### 3. 快速发信（强制 --via）
```powershell
# 必须显式指定 --via，未指定则立即阻断并提示确认
.\mail.ps1 send --via edu --to "professor@university.edu.cn" --subject "课题探讨" --body "王老师您好..."
.\mail.ps1 send --via qq --to "friend@example.com" --subject "生活问候" --body "你好！"
.\mail.ps1 send --via netease --to "hr@company.com" --subject "应聘材料" --body "您好，附件为简历。" --attach "resume.pdf"
```

### 4. 深入具体邮件系统操作
```powershell
# 进入统一邮件系统目录
cd mail-service

# 操作 高校校园邮箱 (Edu Mail)
.\edu.ps1 test
.\edu.ps1 check --limit 5
.\edu.ps1 search --query "面试"

# 操作 QQ 邮箱
.\qq.ps1 test
.\qq.ps1 check --limit 5

# 操作网易 163 邮箱
.\netease.ps1 test
.\netease.ps1 check --limit 5

# 操作 Cloudflare 临时邮箱系统 (进入独立 fmail 目录)
cd ..\fmail
.\fmail.ps1 domains
.\fmail.ps1 accounts
```

### 5. 系统全局体检与诊断中心 (`doctor`)
```powershell
# 一键诊断 4 大模块：4 邮箱通道、推免附件规范、追踪库、垃圾箱误拦截（输出评分）
.\mail.ps1 doctor
```

### 6. 高频微程序操作 (Micro-tools)
```powershell
# 草稿箱管理：秒级查看、一键安全归档测试草稿、安全外发确认
.\mail.ps1 draft list [--via edu]
.\mail.ps1 draft view <ID> [--via edu]
.\mail.ps1 draft clean-test [--via edu]
.\mail.ps1 draft send <ID> --via edu --confirm

# 附件材料库：私有库材料体检、绑定默认学术简历
.\mail.ps1 attach list
.\mail.ps1 attach verify
.\mail.ps1 attach bind <材料名/ID>

# 全邮箱健康巡检与跨文件夹深搜（防漏初审通知）
.\mail.ps1 scan [--via edu]
.\mail.ps1 search-all "推免通知" [--via edu]

# 导师风控查重与防撞车（14天内防重复发信、同单位同实验室冲突预警）
.\mail.ps1 check-mentor "导师姓名" [单位名称]

# 结构化 JSON 数据输出（供程序、脚本或 AI Agent 直接消费）
.\mail.ps1 doctor -Json
.\mail.ps1 draft list -Json
.\mail.ps1 attach list -Json
.\mail.ps1 check-mentor "导师姓名" "单位名称" -Json
```

### 7. 本地可视化 Web 控制台 (前后端分离架构)
```powershell
# 一键启动本地 REST API 服务并自动打开浏览器控制台
.\ui.ps1
# 或通过主入口启动
.\mail.ps1 ui [--port 8000]
```
> **架构设计**：采用标准的**前后端分离设计**。前端为原生 HTML5 + TailwindCSS 单页应用（SPA），后端为 Python 标准库轻量级 HTTP 服务（`web/server.py`），通过纯 JSON REST API 与本地底层 PowerShell 邮件引擎通信，零第三方环境依赖。

### 8. 本地环境初始化向导 (setup-local.ps1)
```powershell
# 首次克隆后一键初始化本地私密配置
.\setup-local.ps1
```

---

## 🔌 RESTful JSON API 接口规范

本地 Web 服务 (`web/server.py`) 提供以下开箱即用的 JSON 接口：

| 请求方式 | 接口端点 | 说明与参数 | 返回结构 |
| :--- | :--- | :--- | :--- |
| **GET** | `/api/doctor` | 全系统健康体检报告 | `{ score: 100, channels: {...}, profile: {...}, issues: [] }` |
| **GET** | `/api/drafts` | 获取草稿箱列表（支持 `?via=edu`） | `[ { id: 1, to: "...", subject: "...", attachments: [...] } ]` |
| **GET** | `/api/draft_detail` | 获取指定草稿全文（`?id=1&via=edu`） | `{ file: "...", to: "...", subject: "...", body: "...", attachments: [...] }` |
| **GET** | `/api/attachments` | 扫描本地推免材料库 | `[ { id: 1, name: "...", size_mb: 4.24, is_default: true, valid: true } ]` |
| **GET** | `/api/scan` | 巡检全邮箱文件夹状态（`?via=edu`） | `{ account: "edu", folders: {...}, risk_alert: false }` |
| **GET** | `/api/profile` | 获取申请人科研画像配置 | `{ name: "...", school: "...", intent: "...", ... }` |
| **POST** | `/api/check_mentor` | 导师投递查重与同组冲突诊断 | `{ name: "...", safe: true, duplicate: false, collision: false, ... }` |

---

## 🔒 隐私保护与安全隔离架构

- **凭证安全**：所有授权码、API 密钥、`.env`、`.credential` 文件均被严格 `.gitignore`，且采用 Windows DPAPI 本地加密存储，绝不泄露至代码仓库。
- **个人资产隔离**：所有个人通讯录 (`contacts.json`)、往来追踪 (`tracking.csv`)、简历附件 (`personal/attachments/`) 均存放在独立的 `personal/` 目录下，与开源核心引擎代码完全物理隔离。
- **物理防误删**：代码层面一票否决所有破坏性删除指令（永久阻断），确保邮件资产 100% 安全。
