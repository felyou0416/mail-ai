# QQ 邮箱专属参考手册 (Reference: QQ Mail)

## 1. 邮箱定位与业务边界
* **账号地址**：`<your_qq_number>@qq.com`
* **适用场景**：
  * 个人日常生活联络、各类互联网平台注册通知与验证码接收。
  * 发送给大众互联网域名（如 Gmail、Outlook、163、各类企业公网域名）。
  * 适合作为测试邮件的发件通道（可替代被封锁的校园邮箱向外部测试域发信）。
* **业务边界**：
  * 个人非学术/非正式事务主力邮箱。

---

## 2. 协议与服务器配置
QQ 邮箱采用腾讯官方标准 IMAP/SMTP 服务：

| 协议 | 服务器节点 | 端口 | SSL/TLS | 认证凭证 |
| :--- | :--- | :--- | :--- | :--- |
| **IMAP 收信** | `imap.qq.com` | `993` | 强制 SSL | 16 位字母授权码 |
| **SMTP 发信** | `smtp.qq.com` | `465` | 强制 SSL | 16 位字母授权码 |

---

## 3. 凭据与安全隔离
* **认证方式**：**必须使用 16 位专用授权码**（严禁使用 QQ 登录密码）。
* **获取途径**：
  1. 网页登录 QQ 邮箱：[mail.qq.com](https://mail.qq.com)
  2. 点击顶部 **设置 → 账户**
  3. 滚动至 **POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV服务**
  4. 开启 **POP3/SMTP服务** 或 **IMAP/SMTP服务**，按页面指引发送短信获取 16 位纯英文授权码。
* **发信一致性要求**：
  * QQ 邮箱 SMTP 网关要求 `From` 必须与登录的 QQ 邮箱地址严格一致，否则会触发 `501 mail from address must be same as authorization user` 错误。
* **隔离存储**：
  * 配置文件：`mail-service/profiles/qq/profile.json`
  * 凭据文件：`mail-service/profiles/qq/.env`
  * DPAPI 加密凭据：`mail-service/profiles/qq/.credential`

---

## 4. 专属资产隔离
* **专属 HTML 签名**：
  * 路径：`mail-service/profiles/qq/signature.html`
  * 内容：简洁的个人签名样式，发信时引擎自动注入。
* **专属附件下载目录**：
  * 路径：`mail-service/profiles/qq/downloads/`
  * QQ 邮箱接收的私人生活附件完全存储于该目录。
* **专属审计日志**：
  * 路径：`mail-service/profiles/qq/mail.log`

---

## 5. 常用命令示例
```powershell
# 测试连接
.\mail-service\core\mail-engine.ps1 -Account qq test

# 查看最新邮件
.\mail-service\core\mail-engine.ps1 -Account qq check --limit 10

# 搜索包含关键字的邮件
.\mail-service\core\mail-engine.ps1 -Account qq search --query "账单"

# 发送邮件（自动附带 QQ 签名）
.\mail-service\core\mail-engine.ps1 -Account qq send --to "friend@example.com" --subject "周末安排" --body "详细日程请查收。"
```
