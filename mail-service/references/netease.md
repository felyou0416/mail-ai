# 网易 163 邮箱专属参考手册 (Reference: NetEase 163 Mail)

## 1. 邮箱定位与业务边界
* **账号地址**：`<your_username>@163.com`
* **适用场景**：
  * 商务洽谈、招聘求职、自由职业合作与商业往来。
  * 适合长期保存工作历史、简历投递与商业合同沟通。
* **反垃圾特性与风控警示（特别注意）**：
  * **网易 163 反垃圾机制极其严苛**（容易触发 `554 DT:SPM` 拦截）。
  * 触发 554 常见原因：短时间内高频连续发信、正文中包含营销词汇/短链接、邮件主题为空或过于简单、无正文仅附件。
  * 防御建议：合理控制发送频率（批量任务至少间隔 30 秒以上），使用规范的主题与正文格式，保持签名完整。

---

## 2. 协议与服务器配置
网易 163 邮箱标准节点配置：

| 协议 | 服务器节点 | 端口 | SSL/TLS | 认证凭证 |
| :--- | :--- | :--- | :--- | :--- |
| **IMAP 收信** | `imap.163.com` | `993` | 强制 SSL | 16 位客户端授权码 |
| **SMTP 发信** | `smtp.163.com` | `465` | 强制 SSL | 16 位客户端授权码 |

---

## 3. 凭据与安全隔离
* **认证方式**：使用 16 位授权码（非网页登录密码）。
* **高安全加密 (DPAPI)**：
  * 已配置 Windows 原生 DPAPI 加密凭据：`mail-service/profiles/netease/.credential`
  * 仅当前机器与当前登录用户可自动解密，跨机器/跨用户无法盗取。
  * 若需重新配置，运行：`.\mail-service\core\setup-credential.ps1 -Profile netease`
* **备用凭据**：
  * `mail-service/profiles/netease/.env`
* **环境隔离**：
  * 底层 bundle 中网易环境变量为 `NETEASE_EMAIL_USER` 与 `NETEASE_EMAIL_PASS`。
  * 引擎每次运行前自动重置清空进程环境变量，确保绝对不会与高校校园邮箱的凭证产生串号交叉！

---

## 4. 专属资产隔离
* **专属 HTML 签名**：
  * 路径：`mail-service/profiles/netease/signature.html`
  * 内容：商务正式落款与联络卡片。
* **专属附件下载目录**：
  * 路径：`mail-service/profiles/netease/downloads/`
  * 商务合同、商业报表、求职简历等附件独立保存。
* **专属审计日志**：
  * 路径：`mail-service/profiles/netease/mail.log`

---

## 5. 常用命令示例
```powershell
# 测试连接（自动优先读取 DPAPI 加密凭据）
.\mail-service\core\mail-engine.ps1 -Account netease test

# 查看收件箱
.\mail-service\core\mail-engine.ps1 -Account netease check --limit 5

# 搜索包含应聘相关邮件
.\mail-service\core\mail-engine.ps1 -Account netease search --query "面试"

# 发送正式业务邮件（自动附带 163 商务签名）
.\mail-service\core\mail-engine.ps1 -Account netease send --to "hr@company.com" --subject "应聘材料 - 姓名" --body "尊敬的HR：您好，附件为最新简历材料，请查收。" --attach "resume.pdf"
```
