# Codex Usage Island Fork

This branch is a Codex-focused derivative of Open Island. It keeps the upstream
GPL-3.0 license, upstream copyright notices, and local-first design, while
specializing the island UI for users who mainly work in Codex Desktop and the
Codex CLI.

中文说明：这个分支是 Open Island 的 Codex 专用改版。它保留原项目 GPL-3.0
许可证、原作者归属和本地优先架构，重点增强 Codex 会话识别、Codex 用量显示、
Codex 刷新倒计时，以及刘海区域的常驻用量提示。

## License And Attribution

- Upstream project: `Octane0411/open-vibe-island`.
- License: GPL-3.0, unchanged. See `LICENSE`.
- This branch is a modified version. The changes below are marked so problems
  in this branch are not attributed to the upstream authors.
- No proprietary OpenAI or Codex code is bundled. The app reads Codex Desktop's
  local app-server through the installed local Codex binary.

## Codex-Specific Goals

This branch intentionally optimizes for a Codex-only workflow:

- Make Codex project and conversation identity visible at a glance.
- Show the current Codex quota remaining and the reset countdown without opening
  a separate usage dashboard.
- Keep the closed notch useful: it shows the short-term Codex remaining quota
  by default.
- Keep the expanded island useful: it separates the short-term and weekly Codex
  windows around the physical notch.
- Avoid leaking account identifiers, local paths, tokens, cookies, or raw Codex
  app-server payloads into committed source.

## Feature Changes

### 1. Codex Quota Source

- Added a Codex app-server JSON-RPC client path for `account/rateLimits/read`.
- The app now prefers Codex Desktop's local app-server quota response.
- Existing rollout `token_count` parsing remains as a fallback.
- The quota reader handles primary and secondary Codex windows:
  - Primary: short-term Codex limit.
  - Secondary: weekly Codex limit.
- The visible UI hides the raw window labels. The island shows remaining
  percentage plus reset countdown, for example `22% 1h15m`.
- The code keeps the internal keys so the two windows can still be routed
  correctly without exposing `5h` or `7d` text in the UI.
- App-server quota snapshots are treated as reliable even at 100% used, so the
  island can display `0%` remaining instead of keeping a stale earlier value.
- The app polls Codex quota adaptively: normally every 30 seconds, every 15
  seconds when quota is low or reset is near, and every 5 seconds when usage is
  depleted or the reset boundary is imminent.

### 2. Closed Notch Usage

- In MacBook notch mode, the closed island now shows Codex short-term remaining
  quota by default.
- The closed island intentionally does not show the weekly window.
- The reset countdown switches to seconds during the final five minutes, for
  example `4m59s`, so reset timing is visible without opening the island.
- The closed pill can expand its left reserve to fit the quota text while
  keeping the physical notch aligned.
- If the app cannot read a reliable Codex quota, the closed island hides the
  quota instead of showing a fake percentage.

### 3. Expanded Notch Layout

- The short-term Codex quota is placed on the left side of the physical notch.
- The weekly Codex quota is placed on the right side of the physical notch.
- The visible `5h` and `7d` labels were removed to reduce clutter.
- Header controls for sound, settings, and quit were moved down beside the
  session overview row.
- The quota chips use wider spacing and padding so the text does not feel
  compressed into the notch corners.

### 4. Codex Conversation Identity

- Codex sessions now combine workspace/project identity with the Codex
  conversation title.
- Repetitive labels such as `Codex.app` and compact `Cx` badges are hidden.
- The row title favors a useful project plus conversation pairing instead of a
  generic injected prompt path.
- Codex conversation names are read from the local session index when available.
- Injected prompt fragments are filtered so rows are easier to distinguish.

### 5. Running State And Runtime

- Codex Desktop thread events are handled more carefully.
- Coarse app-server idle signals are ignored when they would incorrectly mark
  an open Codex thread as completed.
- Running Codex turns can revive a session that was falsely marked completed.
- The session row shows the current turn runtime, helping users distinguish
  active work from stale completed items.
- Permission and question states remain surfaced as actionable sessions.

### 6. Privacy-First Diagnostics

- Added `scripts/codex_usage_probe.py` for local debugging of Codex quota reads.
- The probe redacts token-like, cookie-like, authorization, secret, and session
  fields when raw JSON is requested.
- The probe no longer prints all returned limit ids by default.
- `--show-all-limits` is available for local troubleshooting and partially
  redacts non-default limit ids.
- No personal quota values, local user paths, Codex account ids, or generated
  app bundles are committed by this branch.

### 7. Timed Keep-Awake Control

- Added a local keep-awake menu beside the expanded island sound/settings/quit
  controls.
- Presets cover 15 minutes, 30 minutes, 1 hour, 2 hours, 4 hours, and until
  manually stopped.
- The implementation uses Apple's public IOKit power assertion APIs:
  `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep`.
- No Amphetamine proprietary app code is bundled or copied. Amphetamine's public
  GitHub resources are not the main app source, so this branch implements the
  same class of behavior through documented macOS APIs.
- The feature prevents idle system sleep and idle display sleep while active.
  macOS may still sleep for lid-close, Apple menu sleep, low battery, or other
  non-idle reasons enforced by the system.

### 8. Upstream Auto-Update Disabled

- Removed the Sparkle runtime dependency from the Codex fork.
- The packaged app no longer writes the upstream appcast URL or update public
  key into `Info.plist`.
- The Settings > About pane no longer exposes a working "Check for Updates"
  action; it shows that updates are disabled for this Codex fork.
- This avoids replacing the local Codex quota, notch layout, session identity,
  and keep-awake customizations with a generic upstream release.

## Changed Source Areas

- `Sources/OpenIslandCore/CodexAppServer.swift`
  - Added account rate-limit response models and app-server notification
    handling.
  - Added robust decoding for future-compatible limit fields.
- `Sources/OpenIslandCore/CodexUsage.swift`
  - Added app-server quota loading.
  - Preserved rollout parsing fallback.
  - Treats app-server percentages as reliable while suppressing unreliable
    rollout zeroes.
- `Sources/OpenIslandCore/CodexSessionTracking.swift`
  - Tracks Codex thread names and current turn start time.
  - Filters noisy injected prompts.
- `Sources/OpenIslandCore/SessionState.swift`
  - Carries Codex presentation metadata needed by the UI.
- `Sources/OpenIslandApp/CodexAppServerCoordinator.swift`
  - Streams Codex app-server thread and quota updates into the app model.
  - Avoids false completion from coarse idle events.
- `Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift`
  - Refreshes Codex discovery and preserves thread identity.
- `Sources/OpenIslandApp/AgentSession+Presentation.swift`
  - Presents project plus conversation names and runtime badges.
- `Sources/OpenIslandApp/SleepPreventionController.swift`
  - Creates and releases timed macOS power assertions for the keep-awake menu.
- `Sources/OpenIslandApp/UpdateChecker.swift`
  - Keeps the update-check call sites as no-ops for this custom Codex branch.
- `Sources/OpenIslandApp/Views/IslandPanelView.swift`
  - Implements closed and expanded quota display, hidden labels, notch-aware
    layout, moved header controls, and the keep-awake preset menu.
- `Sources/OpenIslandApp/Views/SettingsView.swift`
  - Replaces the update action with a disabled-update status row.
- `scripts/package-app.sh`, `scripts/launch-dev-app.sh`
  - Stop embedding the upstream appcast URL and Sparkle update metadata.
- `Sources/OpenIslandApp/Views/V6NotchContent.swift`
  - Adds a left closed-notch status area for Codex remaining quota.
- `Tests/OpenIslandCoreTests/CodexSessionTrackingTests.swift`
  - Adds Codex metadata and state-transition coverage.
- `Tests/OpenIslandAppTests/AppModelSessionListTests.swift`
  - Adds UI/session-list behavior coverage for Codex rows.

## Search Keywords

Codex usage island, Codex quota countdown, Codex remaining usage, Codex rate
limit reset, OpenAI Codex macOS notch, Codex Desktop usage widget, Codex agent
session monitor, Open Island Codex fork, Codex dynamic island, Codex status bar,
Codex 5 hour quota, Codex 7 day quota, Codex app-server account rate limits,
AI coding agent notch widget, macOS notch Codex monitor, Codex keep awake,
Codex prevent sleep, macOS IOKit power assertion, Codex fork no auto update.

中文关键词：Codex 用量显示、Codex 剩余额度、Codex 刷新倒计时、Codex 刘海工具、
Codex 桌面版用量、Codex 会话监控、Codex 项目会话名称、Codex 状态栏、
Open Island Codex 分支、AI 编程助手刘海监控、Codex 保持唤醒、Codex 防睡眠、
macOS 防止睡眠、Codex 分支关闭自动更新。

## Safety Notes

- This branch remains local-first. It does not add a remote analytics service.
- It does not commit or require OpenAI API keys.
- It does not store raw Codex app-server payloads.
- It reads local Codex status only from the user's installed Codex environment.
- The diagnostic probe is designed for local debugging and redacts sensitive
  fields by default.
- The keep-awake feature uses local macOS power assertions only. It does not
  require Accessibility access, screen recording, network access, private APIs,
  or copied Amphetamine source.
- Upstream auto-updates are disabled because a generic release can overwrite
  this branch's Codex-specific behavior. Review upstream releases manually
  before cherry-picking changes.
