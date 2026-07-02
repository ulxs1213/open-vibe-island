#!/usr/bin/env python3
"""Print Codex Desktop account rate limits from the local app-server.

This is intentionally a small diagnostic probe: it launches Codex's bundled
`app-server` over stdio, calls `account/rateLimits/read`, and prints only the
quota fields Open Island needs.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import queue
import subprocess
import sys
import threading
import time
from typing import Any


DEFAULT_CODEX = "/Applications/Codex.app/Contents/Resources/codex"


def sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            lowered = key.lower()
            if any(
                marker in lowered
                for marker in ("token", "cookie", "authorization", "secret", "session")
            ):
                sanitized[key] = "[REDACTED]"
            else:
                sanitized[key] = sanitize(item)
        return sanitized

    if isinstance(value, list):
        return [sanitize(item) for item in value]

    return value


class AppServerProbe:
    def __init__(self, codex_path: str) -> None:
        self.process = subprocess.Popen(
            [codex_path, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._next_id = 1
        self._queue: queue.Queue[dict[str, Any]] = queue.Queue()
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._drain_stderr, daemon=True).start()

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()

    def request(self, method: str, params: dict[str, Any] | None = None, timeout: float = 30) -> dict[str, Any]:
        if self.process.stdin is None:
            raise RuntimeError("Codex app-server stdin is unavailable")

        request_id = self._next_id
        self._next_id += 1
        envelope = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params or {},
        }
        self.process.stdin.write(json.dumps(envelope, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                message = self._queue.get(timeout=0.5)
            except queue.Empty:
                continue
            if message.get("id") == request_id:
                return message
        raise TimeoutError(method)

    def _read_stdout(self) -> None:
        if self.process.stdout is None:
            return
        for line in self.process.stdout:
            try:
                self._queue.put(json.loads(line))
            except json.JSONDecodeError:
                continue

    def _drain_stderr(self) -> None:
        if self.process.stderr is None:
            return
        for _ in self.process.stderr:
            pass


def local_time(epoch_seconds: Any) -> str | None:
    if epoch_seconds is None:
        return None
    try:
        return dt.datetime.fromtimestamp(float(epoch_seconds)).isoformat(timespec="seconds")
    except (TypeError, ValueError, OSError):
        return str(epoch_seconds)


def redacted_limit_id(limit_id: str) -> str:
    if limit_id == "codex":
        return limit_id
    if len(limit_id) <= 8:
        return "[REDACTED]"
    return f"{limit_id[:4]}…{limit_id[-4:]}"


def print_rate_limit_snapshot(response: dict[str, Any], raw: bool, show_all_limits: bool) -> None:
    if raw:
        print(json.dumps(sanitize(response), ensure_ascii=False, indent=2))
        return

    result = response.get("result") or {}
    rate_limits = result.get("rateLimits") or {}
    print("SOURCE: Codex app-server account/rateLimits/read")
    print("limit_id:", rate_limits.get("limitId"))
    if show_all_limits:
        print("limit_name:", rate_limits.get("limitName"))
        print("plan_type:", rate_limits.get("planType"))

    for key, label in (("primary", "5h"), ("secondary", "7d")):
        window = rate_limits.get(key) or {}
        resets_at = window.get("resetsAt")
        print(
            f"{label}: used={window.get('usedPercent')}% "
            f"window_mins={window.get('windowDurationMins')} "
            f"resets_at={resets_at} local={local_time(resets_at)}"
        )

    if not show_all_limits:
        return

    reset_credits = result.get("rateLimitResetCredits") or {}
    if "availableCount" in reset_credits:
        print("reset_credits_available:", reset_credits.get("availableCount"))

    print("\nALL_LIMIT_IDS:")
    by_id = result.get("rateLimitsByLimitId") or {}
    for limit_id, snapshot in by_id.items():
        primary = snapshot.get("primary") or {}
        secondary = snapshot.get("secondary") or {}
        print(
            f"- {redacted_limit_id(str(limit_id))}: "
            f"5h_used={primary.get('usedPercent')}% "
            f"5h_reset={local_time(primary.get('resetsAt'))}; "
            f"7d_used={secondary.get('usedPercent')}% "
            f"7d_reset={local_time(secondary.get('resetsAt'))}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", default=DEFAULT_CODEX)
    parser.add_argument("--raw", action="store_true", help="Print sanitized raw JSON response")
    parser.add_argument(
        "--show-all-limits",
        action="store_true",
        help="Print every returned limit id with non-default ids partially redacted",
    )
    args = parser.parse_args()

    probe = AppServerProbe(args.codex)
    try:
        probe.request(
            "initialize",
            {"clientInfo": {"name": "open-island-usage-probe", "version": "0.1.0"}},
        )
        response = probe.request("account/rateLimits/read")
        print_rate_limit_snapshot(response, raw=args.raw, show_all_limits=args.show_all_limits)
    finally:
        probe.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
