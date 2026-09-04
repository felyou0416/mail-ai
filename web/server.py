#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mail-AI 本地服务控制台 - 前后端分离轻量级后端服务 (REST API Server)
基于 Python 内置标准库 http.server，零第三方依赖。
提供 RESTful JSON 接口与静态 Web 前端页面托管。
"""

import http.server
import json
import os
import subprocess
import sys
import urllib.parse
import webbrowser

if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


PORT = 8000
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WEB_DIR = os.path.dirname(os.path.abspath(__file__))


def run_ps1_json(args_list):
    """运行 powershell 脚本并捕获 JSON 输出"""
    cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File"] + args_list
    try:
        proc = subprocess.run(
            cmd,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="ignore",
            timeout=30,
        )
        stdout = proc.stdout.strip()
        # 提取第一个有效的 JSON 片段
        if stdout.startswith("{") or stdout.startswith("["):
            return json.loads(stdout)
        # 尝试查找 JSON
        start_idx = -1
        for i, ch in enumerate(stdout):
            if ch in ("{", "["):
                start_idx = i
                break
        if start_idx != -1:
            return json.loads(stdout[start_idx:])
        return {"raw_output": stdout, "exit_code": proc.returncode}
    except Exception as e:
        return {"error": str(e)}


class MailAIRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # 1. API: 系统体检
        if path == "/api/doctor":
            script = os.path.join(PROJECT_ROOT, "mail-service", "core", "system-doctor.ps1")
            data = run_ps1_json([script, "-Json"])
            return self.send_json(data)

        # 2. API: 草稿箱列表
        if path == "/api/drafts":
            via = query.get("via", ["edu"])[0]
            script = os.path.join(PROJECT_ROOT, "mail-service", "core", "draft-manager.ps1")
            data = run_ps1_json([script, "list", "-Json", "--via", via])
            return self.send_json(data)

        # 3. API: 草稿详情
        if path == "/api/draft_detail":
            target = query.get("id", ["1"])[0]
            via = query.get("via", ["edu"])[0]
            script = os.path.join(PROJECT_ROOT, "mail-service", "core", "draft-manager.ps1")
            data = run_ps1_json([script, "view", target, "-Json", "--via", via])
            return self.send_json(data)

        # 4. API: 附件材料库
        if path == "/api/attachments":
            script = os.path.join(PROJECT_ROOT, "套磁信", "core", "engine", "attachment-manager.ps1")
            data = run_ps1_json([script, "list", "-Json"])
            return self.send_json(data)

        # 5. API: 全箱扫描
        if path == "/api/scan":
            via = query.get("via", ["edu"])[0]
            script = os.path.join(PROJECT_ROOT, "mail-service", "core", "mailbox-inspector.ps1")
            data = run_ps1_json([script, "scan", "-Json", "--via", via])
            return self.send_json(data)

        # 6. API: 个人画像与配置
        if path == "/api/profile":
            p_file = os.path.join(PROJECT_ROOT, "套磁信", "personal", "profile.json")
            if not os.path.exists(p_file):
                p_file = os.path.join(PROJECT_ROOT, "套磁信", "core", "schemas", "student_profile.sample.json")
            profile_data = {}
            if os.path.exists(p_file):
                try:
                    with open(p_file, "r", encoding="utf-8") as f:
                        profile_data = json.load(f)
                except Exception:
                    pass
            return self.send_json(profile_data)

        # 默认静态页面
        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # 读取请求 Body
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length).decode("utf-8")
        body_json = {}
        if post_data:
            try:
                body_json = json.loads(post_data)
            except Exception:
                pass

        # 7. API: 导师风控查重
        if path == "/api/check_mentor":
            name = body_json.get("name", "")
            org = body_json.get("org", "")
            email = body_json.get("email", "")
            script = os.path.join(PROJECT_ROOT, "套磁信", "core", "engine", "mentor-checker.ps1")
            args = [script, "-Json"]
            if name:
                args.extend(["--name", name])
            if org:
                args.extend(["--org", org])
            if email:
                args.extend(["--email", email])
            data = run_ps1_json(args)
            return self.send_json(data)

        return self.send_json({"error": "Endpoint not found"}, 404)


def main():
    port = PORT
    auto_open = False

    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a in ("--port", "-p") and i + 1 < len(args):
            port = int(args[i + 1])
        if a in ("--open", "-o"):
            auto_open = True

    server_address = ("", port)
    httpd = http.server.ThreadingHTTPServer(server_address, MailAIRequestHandler)
    url = f"http://localhost:{port}"

    print(f"=================================================================")
    print(f"  Mail-AI 本地控制台服务已启动 (前后端分离架构)")
    print(f"  Web 前端地址: {url}")
    print(f"  REST API 根路径: {url}/api/")
    print(f"=================================================================")

    if auto_open:
        webbrowser.open(url)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n服务已平稳关闭。")


if __name__ == "__main__":
    main()
