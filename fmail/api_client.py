"""
Cloudflare Temp Email API Helper
================================
安全说明(最高禁令):
  - ⛔ 永远禁止删除任何邮件：脚本完全阻断所有删除接口与端点。
  - 默认 API 端点：https://mail.example.com（可通过环境变量 CF_TEMP_MAIL_URL 或 --url 覆盖）。
  - 新建邮箱凭证默认保存到 ~/.cf-temp-mail/credentials.json，可用 accounts 查看。
"""
import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from email import policy
from email.parser import BytesParser
from pathlib import Path

# 确保在 Windows 控制台或后台调用时输出 UTF-8，避免 cp1252 编码崩溃
if sys.platform == "win32":
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# 默认 API 端点
DEFAULT_BASE_URL = os.environ.get("CF_TEMP_MAIL_URL", "https://mail.example.com")

# 凭证存储位置：~/.cf-temp-mail/credentials.json
CRED_DIR = Path.home() / ".cf-temp-mail"
CRED_FILE = CRED_DIR / "credentials.json"

# 主动禁止的危险路径（命中即拒绝，防误删）
BLOCKED_DANGEROUS_PATHS = {
    "/admin/mails",          # DELETE 不带 id 会清空 ALL 邮件
    "/admin/mails/",         # 末尾斜杠变体
}

def make_request(url, method="GET", headers=None, data=None):
    # 默认带浏览器 User-Agent，否则会被 Cloudflare 机器人防护拦截（error 1010）
    default_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    if headers is None:
        headers = {}
    headers = {**{"User-Agent": default_ua}, **headers}

    # 危险路径防火墙：针对 DELETE/POST/PUT 的整站级批量端点
    if method in ("DELETE", "POST", "PUT"):
        try:
            from urllib.parse import urlparse
            parsed = urlparse(url)
            path = parsed.path or ""
        except Exception:
            path = url.split("//", 1)[-1].split("/", 1)[-1].split("?", 1)[0]
            path = "/" + path if not path.startswith("/") else path
        clean = path.rstrip("/")
        if clean in BLOCKED_DANGEROUS_PATHS or method == "DELETE":
            raise RuntimeError(
                f"[SAFETY BLOCKED] Refusing {method} {path}: Email deletion is permanently disabled by safety policy."
            )

    req = urllib.request.Request(url, method=method, headers=headers)
    if data:
        req.data = json.dumps(data).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8")
            return e.code, json.loads(body)
        except Exception:
            return e.code, body if 'body' in locals() else str(e)
    except Exception as e:
        return 500, str(e)

def load_creds():
    if CRED_FILE.exists():
        try:
            data = json.loads(CRED_FILE.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                return {}
            # 兼容处理：如果存在旧版单账号扁平格式 {"address": "...", "jwt": "...", ...}
            if "address" in data and "jwt" in data and data["address"] not in data:
                addr = data["address"]
                data[addr] = {
                    "jwt": data["jwt"],
                    "name": addr.split("@")[0],
                    "domain": addr.split("@")[-1] if "@" in addr else "",
                    "created_at": "历史凭据"
                }
            return data
        except Exception:
            return {}
    return {}

def save_creds(creds):
    CRED_DIR.mkdir(parents=True, exist_ok=True)
    CRED_FILE.write_text(json.dumps(creds, ensure_ascii=False, indent=2), encoding="utf-8")

def resolve_jwt(args):
    # 优先级：--jwt > --addr（从本地凭证库读取） > 本地最近创建的邮箱
    if args.jwt:
        return args.jwt, None
    creds = load_creds()
    if args.addr:
        entry = creds.get(args.addr)
        if isinstance(entry, dict) and entry.get("jwt"):
            return entry["jwt"], None
        return None, f"未找到邮箱 {args.addr} 的本地凭证（请先 create，或显式传入 --jwt）"
    
    # 若未指定 addr 也未指定 jwt，尝试使用最近的一个保存邮箱
    boxes = [v for k, v in creds.items() if isinstance(v, dict) and v.get("jwt")]
    if boxes:
        boxes_sorted = sorted(boxes, key=lambda x: x.get("created_at", ""), reverse=True)
        return boxes_sorted[0]["jwt"], None

    return None, "请指定 --addr <邮箱地址> 或 --jwt <token>"

def parse_headers(raw):
    try:
        msg = BytesParser(policy=policy.default).parsebytes(raw.encode("utf-8", errors="replace"))
        return str(msg.get("From") or ""), str(msg.get("Subject") or "")
    except Exception:
        return "", ""

def extract_mail_full(raw):
    try:
        msg = BytesParser(policy=policy.default).parsebytes(raw.encode("utf-8", errors="replace"))
        headers = {
            "From": str(msg.get("From") or ""),
            "To": str(msg.get("To") or ""),
            "Subject": str(msg.get("Subject") or ""),
            "Date": str(msg.get("Date") or ""),
        }
        body = ""
        try:
            body_part = msg.get_body(preferencelist=("plain", "html"))
            if body_part:
                body = body_part.get_content()
            else:
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() in ("text/plain", "text/html"):
                            body = part.get_content()
                            break
                else:
                    body = msg.get_content()
        except Exception:
            body = raw
        return headers, body
    except Exception as e:
        return {"From": "", "To": "", "Subject": "", "Date": ""}, f"[解析失败: {e}]\n{raw}"

def main():
    parser = argparse.ArgumentParser(
        description="Cloudflare Temp Email API Helper · 高可用增强版",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "安全禁令:\n"
            "  - ⛔ 永远禁止删除邮件：本脚本已完全移除/阻断删除能力。\n"
            "  - 默认 URL: https://mail.example.com\n"
        ),
    )
    parser.add_argument("--url", default=DEFAULT_BASE_URL, help=f"API Base URL (默认: {DEFAULT_BASE_URL})")
    parser.add_argument("--action", required=True,
                        choices=["domains", "create", "list", "fetch", "send", "accounts",
                                 "admin-addresses", "admin-mails"],
                        help="执行的操作")
    parser.add_argument("--name", help="邮箱前缀（用于 create）")
    parser.add_argument("--domain", help="邮箱域名（用于 create）")
    parser.add_argument("--no-save", action="store_true", help="创建后不保存凭证")
    parser.add_argument("--jwt", help="JWT 认证 Token")
    parser.add_argument("--addr", help="邮箱地址（自动匹配本地凭证中的 JWT）")
    parser.add_argument("--mail-id", type=int, help="邮件 ID（用于 fetch）")
    parser.add_argument("--to", help="收件人邮箱（用于 send）")
    parser.add_argument("--subject", help="邮件主题（用于 send）")
    parser.add_argument("--content", help="邮件正文（用于 send）")
    parser.add_argument("--limit", type=int, default=20, help="返回数量限制 (默认 20)")
    parser.add_argument("--admin-password", help="管理员密码 (或环境变量 CF_TEMP_MAIL_ADMIN_PASSWORD)")

    args = parser.parse_args()
    base_url = args.url.rstrip("/")

    if args.action == "domains":
        status, res = make_request(f"{base_url}/open_api/settings")
        if status == 200:
            domains = res.get("domains", [])
            print(f"可用域名列表 ({len(domains)} 个):", domains)
        else:
            print(f"请求失败 ({status}):", res)

    elif args.action == "create":
        domain = args.domain
        if not domain:
            # 自动获取第一个可用域名
            status_d, res_d = make_request(f"{base_url}/open_api/settings")
            if status_d == 200 and res_d.get("domains"):
                domain = res_d["domains"][0]
                print(f"[提示] 未指定 --domain，自动采用首选域名: {domain}")
            else:
                print("错误: 请指定 --domain 邮箱域名")
                return

        payload = {"name": args.name or "", "domain": domain}
        status, res = make_request(f"{base_url}/api/new_address", method="POST", data=payload)
        if status == 200:
            addr = res.get("address")
            jwt = res.get("jwt")
            print("✓ 成功创建临时邮箱:")
            print("  地址:", addr)
            print("  JWT Token:", jwt)
            if not args.no_save and jwt and addr:
                creds = load_creds()
                creds[addr] = {
                    "jwt": jwt,
                    "name": args.name or "",
                    "domain": domain,
                    "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                }
                save_creds(creds)
                print(f"  凭据已自动保存至: {CRED_FILE}")
        else:
            print(f"创建失败 ({status}):", res)

    elif args.action == "list":
        jwt, err = resolve_jwt(args)
        if err:
            print("错误:", err)
            return
        headers = {"Authorization": f"Bearer {jwt}"}
        status, res = make_request(f"{base_url}/api/mails?limit={args.limit}&offset=0", headers=headers)
        if status == 200:
            count = res.get("count", 0)
            results = res.get("results", [])
            print(f"收件箱邮件列表 (共 {count} 封):")
            if not results:
                print("  (收件箱暂无邮件)")
            for mail in results:
                from_, subject_ = parse_headers(mail.get("raw") or "")
                if not from_:
                    from_ = mail.get("source") or "未知发件人"
                created_at = mail.get("created_at") or "-"
                print(f"- ID: {mail.get('id')} | 时间: {created_at} | 来自: {from_} | 主题: {subject_}")
        else:
            print(f"获取失败 ({status}):", res)

    elif args.action == "fetch":
        if not args.mail_id:
            print("错误: 请通过 --mail-id <数字ID> 指定要查看的邮件")
            return
        jwt, err = resolve_jwt(args)
        if err:
            print("错误:", err)
            return
        headers = {"Authorization": f"Bearer {jwt}"}
        # 首先查询邮件列表获取对应 mail_id 的 raw
        status, res = make_request(f"{base_url}/api/mails?limit=100&offset=0", headers=headers)
        if status == 200:
            results = res.get("results", [])
            target = None
            for m in results:
                if m.get("id") == args.mail_id:
                    target = m
                    break
            if not target:
                print(f"未在当前邮箱前 100 封邮件中找到 ID={args.mail_id} 的邮件")
                return

            raw = target.get("raw") or ""
            headers_dict, body_content = extract_mail_full(raw)
            print("=" * 60)
            print(f"邮件详情 [ID: {args.mail_id}]")
            print(f"发件人: {headers_dict['From']}")
            print(f"收件人: {headers_dict['To']}")
            print(f"时间:   {headers_dict['Date'] or target.get('created_at')}")
            print(f"主题:   {headers_dict['Subject']}")
            print("-" * 60)
            print(body_content.strip())
            print("=" * 60)
        else:
            print(f"获取失败 ({status}):", res)

    elif args.action == "send":
        if not args.to or not args.subject or not args.content:
            print("错误: 发送邮件必须指定 --to, --subject, --content")
            return
        jwt, err = resolve_jwt(args)
        if err:
            print("错误:", err)
            return
        headers = {"Authorization": f"Bearer {jwt}"}
        payload = {
            "to_mail": args.to,
            "subject": args.subject,
            "content": args.content,
            "is_html": False
        }
        status, res = make_request(f"{base_url}/api/send_mail", method="POST", headers=headers, data=payload)
        if status == 200:
            print("✓ 邮件发送成功！")
        else:
            print(f"发送失败 ({status}):", res)

    elif args.action == "accounts":
        creds = load_creds()
        boxes = {k: v for k, v in creds.items() if isinstance(v, dict)}
        if not boxes:
            print("本地暂无保存的邮箱凭据。使用 create 创建后将自动记录。")
            return
        print(f"已保存的临时邮箱 ({len(boxes)} 个) [保存在 {CRED_FILE}]:")
        for addr, e in sorted(boxes.items(), key=lambda kv: kv[1].get("created_at", "") or "", reverse=True):
            print(f"- {addr} | 创建时间: {e.get('created_at') or '-'} | 前缀: {e.get('name') or '-'}")

    elif args.action in ("admin-addresses", "admin-mails"):
        pwd = (args.admin_password
               or os.environ.get("CF_TEMP_MAIL_ADMIN_PASSWORD", "")
               or (load_creds().get("admin_password") if isinstance(load_creds().get("admin_password"), str) else ""))
        if not pwd:
            print("错误: 需要管理员密码。请使用 --admin-password 或设置环境变量 CF_TEMP_MAIL_ADMIN_PASSWORD")
            return
        headers = {"x-admin-auth": pwd}
        path = "/admin/address" if args.action == "admin-addresses" else "/admin/mails"
        status, res = make_request(f"{base_url}{path}?limit={args.limit}&offset=0", headers=headers)
        if status == 200:
            results = res.get("results", []) if isinstance(res, dict) else res
            count = res.get("count", len(results)) if isinstance(res, dict) else len(results)
            print(f"{args.action} (共 {count} 条):")
            for item in results:
                print("-", json.dumps(item, ensure_ascii=False)[:240])
        else:
            print(f"请求失败 ({status}):", res)

if __name__ == "__main__":
    main()
