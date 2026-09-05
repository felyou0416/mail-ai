# 高校校园邮箱专属参考手册 (Reference: Edu Mail)

## 1. 邮箱定位与业务边界
* **账号标识**：`edu`（通用高校校园邮箱，全校师生官方认证邮箱）
* **配置范例**：`<your_student_id>@your_school.edu.cn`
* **适用场景**：
  * 校内教学、科研实验、选课、教务与学籍等官方事务。
  * 导师联络、实验室课题组同学、教务秘书日常沟通。
  * 学术期刊投稿、学术会议交流、学术夏令营/推免套磁申请（**高校导师通常最重视来自 .edu.cn 的邮件**）。
* **⛔ 严禁使用场景（风控隔离）**：
  * **严禁用于发送一次性匿名临时测试邮箱（如各类公开临时域）**。
  * 原因：高校校园邮箱受教育网与反垃圾网关严格监控，频繁向匿名/临时域发信会被网关判定为异常外发，可能导致个人邮箱被锁定，甚至影响全校 IP/域信誉！测试邮件请使用 QQ、网易或临时邮箱系统。

---

## 2. 常见高校邮箱底座与配置参考

国内高校通常由以下三大平台提供邮件技术底座支持，协议均为标准 IMAP/SMTP：

| 邮箱底座平台 | 代表高校 | IMAP 服务器 (端口 993 SSL) | SMTP 服务器 (端口 465 SSL) | 认证机制 |
| :--- | :--- | :--- | :--- | :--- |
| **网易企业邮底座** | 清华、人大、多所综合大学等 | `imaphz.qiye.163.com` | `smtphz.qiye.163.com` | 账号 + 客户端专用授权码/密码 |
| **腾讯企业邮底座** | 北大、复旦、浙大等 | `imap.exmail.qq.com` | `smtp.exmail.qq.com` | 账号 + 客户端专用授权码 |
| **Coremail 自建底座** | 华科、中科大、西交等 | `mail.xxx.edu.cn` | `mail.xxx.edu.cn` | 统一身份认证密码 / 独立邮箱密码 |

---

## 3. 资产与凭证隔离架构
* 配置文件：`mail-ai/profiles/edu/profile.json`（可从 `profile.sample.json` 复制）
* 凭据文件：`mail-ai/profiles/edu/.env`（受 `.gitignore` 保护）
* 个性化签名：`mail-ai/profiles/edu/signature.html`（受 `.gitignore` 保护）
* 通讯录：`mail-ai/profiles/edu/contacts.json`
* 独立附件下载：`mail-ai/profiles/edu/downloads/`
* 审计日志：`mail-ai/profiles/edu/mail.log`

---

## 4. 常用命令示例

```powershell
# 1. 快捷专属入口
.\mail-ai\edu.ps1 test
.\mail-ai\edu.ps1 check --limit 5
.\mail-ai\edu.ps1 search --query "录取通知"

# 2. 顶层入口调度 (--via edu，默认通道)
.\mail.ps1 test --via edu
.\mail.ps1 check --limit 5
.\mail.ps1 send --via edu --to "professor@university.edu.cn" --subject "学术探讨" --body "王老师您好..."
```
