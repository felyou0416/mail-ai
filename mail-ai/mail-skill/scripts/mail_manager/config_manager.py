"""Configuration manager for mail-skill.

Reads configuration from config.txt file using dotenv, with automatic
bridge support for mail-ai profile configurations (mail-ai/profiles).
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

_PROJECT_ROOT: str | None = None


def _get_project_root() -> str:
    """Get the root directory of the mail-skill project.

    __file__ is at scripts/mail_manager/config_manager.py, so 3 dirname
    levels resolve to the mail-skill project root.
    """
    global _PROJECT_ROOT
    if _PROJECT_ROOT is None:
        try:
            _PROJECT_ROOT = os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            )
        except NameError:
            _PROJECT_ROOT = os.getcwd()
    return _PROJECT_ROOT


def _parse_env_file(path: str) -> dict[str, str]:
    """Parse a simple .env file into key-value pairs."""
    env_vars: dict[str, str] = {}
    if not os.path.isfile(path):
        return env_vars
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env_vars[k.strip()] = v.strip().strip("'\"")
    except Exception as e:
        logger.debug(f"Failed to read {path}: {e}")
    return env_vars


def _load_mail_service_profiles() -> dict[str, dict[str, Any]]:
    """Auto-discover accounts from mail-ai/profiles directory in parent repo."""
    accounts: dict[str, dict[str, Any]] = {}
    parent_root = os.path.dirname(_get_project_root())
    profiles_dir = os.path.join(parent_root, "profiles")
    if not os.path.isdir(profiles_dir):
        return accounts

    def _safe_int(val: Any, default: int) -> int:
        try:
            return int(str(val).strip()) if val else default
        except (ValueError, TypeError):
            return default

    for item in sorted(os.listdir(profiles_dir)):
        item_dir = os.path.join(profiles_dir, item)
        if not os.path.isdir(item_dir):
            continue

        profile_json_path = os.path.join(item_dir, "profile.json")
        env_path = os.path.join(item_dir, ".env")
        if not os.path.isfile(profile_json_path):
            continue

        try:
            with open(profile_json_path, "r", encoding="utf-8") as f:
                p_data = json.load(f)
        except Exception as e:
            logger.debug(f"Failed to load {profile_json_path}: {e}")
            continue

        env_vars = _parse_env_file(env_path)
        env_user_key = p_data.get("envUserKey", "")
        env_pass_key = p_data.get("envPassKey", "")

        email_val = env_vars.get(env_user_key) or p_data.get("email")
        password_val = env_vars.get(env_pass_key) or env_vars.get("PASSWORD")

        # Skip sample / placeholder accounts
        if not email_val or "example.com" in email_val or "your_" in email_val:
            continue
        if not password_val:
            continue

        account_entry: dict[str, Any] = {
            "EMAIL": email_val,
            "PASSWORD": password_val,
            "PROTOCOL": "imap",
            "IMAP_SERVER": p_data.get("imapHost"),
            "IMAP_PORT": _safe_int(p_data.get("imapPort"), 993),
            "POP3_SERVER": p_data.get("pop3Host"),
            "POP3_PORT": _safe_int(p_data.get("pop3Port"), 995),
            "SMTP_SERVER": p_data.get("smtpHost"),
            "SMTP_PORT": _safe_int(p_data.get("smtpPort"), 465),
            "USE_SSL": True,
            "ALIAS": item,
            "DISPLAY_NAME": p_data.get("displayName", item),
        }
        accounts[email_val] = account_entry

    return accounts


def load_config() -> dict[str, Any]:
    """Load configuration from config.txt file or auto-bridged profiles."""
    config_path = _find_config_file()
    if config_path:
        try:
            load_dotenv(config_path, override=True)
        except Exception as e:
            logger.warning(f"Failed to load {config_path}: {e}")

    project_root = _get_project_root()

    storage_root = os.getenv(
        "MAIL_STORAGE_ROOT", os.path.join(project_root, "mail_data")
    )
    if not os.path.isabs(storage_root):
        storage_root = os.path.abspath(os.path.join(project_root, storage_root))

    db_path = os.getenv(
        "MAIL_DB_PATH", os.path.join(storage_root, "mail_index.db")
    )
    if not os.path.isabs(db_path):
        db_path = os.path.abspath(os.path.join(storage_root, db_path))

    attachment_path = os.getenv(
        "MAIL_ATTACHMENT_PATH", os.path.join(storage_root, "attachments")
    )
    if not os.path.isabs(attachment_path):
        attachment_path = os.path.abspath(os.path.join(storage_root, attachment_path))

    config: dict[str, Any] = {
        "STORAGE_ROOT": storage_root,
        "DB_PATH": db_path,
        "ATTACHMENT_PATH": attachment_path,
        "ACCOUNTS": {},
    }

    # 1. Load accounts explicitly configured via MAIL_ACCOUNT_* env vars
    account_prefixes = set()
    for key in os.environ:
        if key.startswith("MAIL_ACCOUNT_") and key.endswith("_EMAIL"):
            prefix = key[:-6]
            account_prefixes.add(prefix)

    for prefix in sorted(account_prefixes):
        email = os.getenv(f"{prefix}_EMAIL")
        if not email:
            continue

        use_ssl_raw = os.getenv(f"{prefix}_USE_SSL", "true").lower()
        use_ssl = use_ssl_raw in ("true", "1", "yes")

        def _safe_int(val: str | None, default: int) -> int:
            try:
                return int(val.strip()) if val else default
            except (ValueError, TypeError):
                return default

        config["ACCOUNTS"][email] = {
            "EMAIL": email,
            "PASSWORD": os.getenv(f"{prefix}_PASSWORD"),
            "PROTOCOL": os.getenv(f"{prefix}_PROTOCOL", "imap"),
            "IMAP_SERVER": os.getenv(f"{prefix}_IMAP_SERVER"),
            "IMAP_PORT": _safe_int(os.getenv(f"{prefix}_IMAP_PORT"), 993),
            "POP3_SERVER": os.getenv(f"{prefix}_POP3_SERVER"),
            "POP3_PORT": _safe_int(os.getenv(f"{prefix}_POP3_PORT"), 995),
            "SMTP_SERVER": os.getenv(f"{prefix}_SMTP_SERVER"),
            "SMTP_PORT": _safe_int(os.getenv(f"{prefix}_SMTP_PORT"), 465),
            "USE_SSL": use_ssl,
        }

    # 2. Bridge accounts from parent mail-ai/profiles if not already present
    bridged = _load_mail_service_profiles()
    for email_addr, acc_info in bridged.items():
        if email_addr not in config["ACCOUNTS"]:
            config["ACCOUNTS"][email_addr] = acc_info

    return config


def _find_config_file() -> str | None:
    """Search for config.txt or .env file in standard locations."""
    root = _get_project_root()
    parent_root = os.path.dirname(root)
    candidates = [
        os.path.join(root, "config.txt"),
        os.path.join(os.getcwd(), "config.txt"),
        os.path.join(parent_root, "config.txt"),
        os.path.join(root, ".env"),
        os.path.join(parent_root, ".env"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None
