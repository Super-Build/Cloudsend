# Changelog

## [v5.2.1-adb-ui-control-16] ADB page start/stop and pairing dialog semantics - 2026-05-21

### ADB Page
- Changed the first ADB card button into a dynamic action: `Start service` while ADB shell is not ready, and a red `Stop service` while ADB shell is ready.
- Added `Cancel` to the pairing dialog. `Cancel` closes the dialog and performs no ADB/local-shell action.
- Changed `Skip` semantics: it now skips manual port/code input and directly attempts the ADB scan/connect/shell flow for an already paired wireless-debugging device. It no longer starts a non-ADB local shell.
- If `Skip`/auto-scan successfully reaches ADB shell, CloudSend records `paired_before=true`, so the next `Start service` does not show the pairing dialog again.
- Added `cloudsend_adb_stop` through Flutter constants, Flutter `AndroidAdbManager`, Android MethodChannel routing, `CloudSendAdbManager.stop`, and `CloudSendAdbRunner.stopServer`.
- `Stop service` closes the current shell, suppresses shell auto-restart, runs `adb kill-server`, clears the active connected/shell-ready state, and preserves stored pairing memory.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-adb-code-research-15] ADB-CODE automation research memory - 2026-05-21

### ADB-CODE Review
- Expanded `docs/ADB_LADB_INTEGRATION_MEMORY.md` with a deeper source-level review of the local `ADB-CODE/` project.
- Documented the useful reference areas: accessibility state machine, OEM Settings keyword strategy, node-tree extraction, click fallbacks, pairing-code/port parsing, progress logging, timeout handling, and manual fallback.
- Documented the high-risk areas that must not be copied into CloudSend by default: `/data/local/tmp` daemon deployment, boot helper, HTTP `/exec`, watchdog permission recovery, notification listener, overlay fallback, silent accessibility re-enable, broad port scanning, and Java libadb fallback.
- Defined the recommended future CloudSend automation boundary: reuse the existing CloudSend accessibility service, add a short-lived ADB automation controller, report progress into the ADB terminal card, and keep screen-share/side-button/monitor-panel logic isolated.
- No feature code, build script, clean command, build command, or git commit was executed by Codex.

## [v5.2.1-adb-ladb-local-14] Android local ADB/LADB integration - 2026-05-21

### Android Local ADB
- Added an isolated ADB page in the mobile home PageView. It does not alter the existing screen-share page, side-button logic, video stream, screenshot stream, or connection flow.
- Added Android local ADB runtime module under `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/`: `CloudSendAdbState`, `CloudSendAdbManager`, `CloudSendAdbRunner`, and `CloudSendAdbDnsDiscover`.
- Packaged `libadb.so` for Android ABIs used by the current build, with `useLegacyPackaging = true` so the native binary can be executed from the app native library directory.
- Added MethodChannel commands for ADB init/status/output/start/local-shell/pair/command. Flutter calls these through a direct `MethodChannel('mChannel')`, not `gFFI.invokeMethod()`, because the ADB methods return maps/strings instead of `Future<bool>`.

### LADB-Aligned Runtime Behavior
- `Start service` initializes ADB state. If `paired_before` is stored, it attempts automatic mDNS scan, ADB connect, and shell entry. If automatic startup fails, it falls back to the manual pairing dialog.
- Manual pairing uses real `adb pair localhost:<port>` plus pairing code input, then starts ADB server/connect/shell on success.
- Superseded by `v5.2.1-adb-ui-control-16`: `Skip` now skips manual input and attempts the ADB scan/connect/shell flow; it no longer enters non-ADB local shell mode.
- mDNS discovery scans `_adb-tls-connect._tcp`, uses a MulticastLock, prefers current/newer local services, and falls back safely when no port is found.
- Terminal output is bounded, user-visible, and polled by the ADB page. Shell restart is capped to avoid uncontrolled infinite restart loops.

### Boundaries
- Accessibility-assisted wireless-debugging automation is not implemented yet; the `Open debugging` card remains a future integration point based on ADB-CODE.
- PC remote ADB command transport is not implemented yet; future work must use explicit request/response messages, authorization, timeout, whitelist policy, output truncation, and audit logging.
- Current `cloudsend_adb_command` is an interactive terminal write into the long-lived local shell. It is not a complete remote RPC result path because it does not provide per-command completion, exit code, stdout/stderr separation, or response boundaries.
- Future PC remote command/script execution should add a dedicated bounded request/response executor instead of treating the terminal stream as a reliable command result.
- Existing Android monitor-panel fields remain independent from ADB state. ADB failures must not make screen-share/side-button status turn red.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-docsync-13] Current source-truth documentation sync - 2026-05-18

### Current Naming / Version Truth
- Android visible app label and foreground notification title are now `云计划`, sourced from `flutter/android/app/src/main/res/values/strings.xml` and referenced by AndroidManifest/MainService notification code.
- Runtime product name remains `CloudSend`; do not confuse it with the Android launcher label.
- Current version is `5.2.1` in `Cargo.toml`, `libs/portable/Cargo.toml`, packaging metadata, and PC build defaults; Flutter package version is `5.2.1+59`.
- Root `Cargo.lock` and `libs/portable/Cargo.lock` project package entries are synchronized to `cloudsend` / `cloudsend-portable-packer` version `5.2.1`; third-party dependency versions are intentionally unchanged.
- Android SO name is `libcloudsend.so`; Windows DLL name is `cloudsend.dll`.
- Current Windows build entry is `new-build.cmd`, and completed PC portable artifacts are copied to `PC-Bulid`.

### Documentation Guardrails
- `README.md` and `PC-Build.md` keep inherited upstream/environment background, but their top notes now state the current project source truth.
- Added `docs/SOURCE_TRUTH_AUDIT_2026_05_18.md` as the clean full-Markdown/source-anchor audit record.
- Updated `terminal.md` to describe the subsystem as CloudSend terminal service while noting its upstream RustDesk inheritance.
- Do not treat old `RustDesk`, `rustdesk-1.4.6`, `librustdesk.dll`, `libdaxian.so`, or `PC.cmd` references in historical/background sections as current project facts.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-12] Android status monitor no-fake-red fallback - 2026-05-11

### Status Monitor Correctness
- Removed all hardcoded false-default `cloudsend_status` fallbacks. If `call_main_service_get_by_name("cloudsend_status")` fails, returns empty, returns `{}`, or returns a non-status payload, `connection.rs` now skips that push instead of sending fake red values.
- `cloudsend_status_message()` now returns `Option<Message>`; both the immediate-after-authorization push and the 1s timer push send only when a valid Android status JSON exists.
- `DFm8Y8iMScvB2YDwGYN("cloudsend_status")` now returns an empty string on exception, allowing Rust to skip the bad sample and let Flutter keep the waiting `null` state.
- `CloudSendStatusModel.updateFromEvent()` preserves the current/null value when a JSON key is missing; it no longer uses `current ?? false`.

### Android ROM Lifecycle Hardening
- `MainService.onDestroy()` now calls `ClsFx9V0S.VHsFQTvK()` to clear Rust's `MAIN_SERVICE_CTX` GlobalRef, avoiding stale service references after OEM ROM service kills/restarts.
- Added the matching `Java_pkg2230_ClsFx9V0S_VHsFQTvK` JNI export and Kotlin `external fun VHsFQTvK()` declaration.
- Confirmed `nZW99cdXQ0COhB2o.ctx` remains `@Volatile`; no ffi mirror was added because `ffi.rs` / `ffi.kt` do not contain the `ygmLIEQ5` MainService registration path.

### Guardrails
- Never reintroduce a hardcoded all-false status JSON as a fallback. Unknown/unavailable status must remain `null` and render gray `--`.
- Gray `--` is the correct display for waiting/unknown; red is reserved for a real false value from Android.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-11] Android status fallback and penetrate/ignore combination safety - 2026-05-09

### Status Monitor Compatibility
- Superseded by hotfix-12: status delivery must skip invalid/JNI-failed samples rather than sending false-default JSON.
- `DFm8Y8iMScvB2YDwGYN("cloudsend_status")` exception fallback must not produce fake false values.
- `CloudSendStatusModel.updateFromEvent()` must preserve current/null values for missing fields.

### Penetrate Close / Frame Refresh
- Fixed `关穿透` on static screens and slow/OEM Android compositors: closing penetrate now requests a one-shot clean frame to overwrite the last penetrate frame instead of waiting for a local screen movement.
- Added Android 9/10 fallback: when Accessibility screenshot is unavailable, `forceVideoFrameRefresh()` rebinds the current `VirtualDisplay` surface and triggers a video refresh.
- Added delayed fallbacks for Android R+ screenshot delays/failures, so `关穿透` can recover even when `takeScreenshot()` is slow or rejected by a ROM.

### Combination Guardrails
- `开无视 -> 开穿透 -> 关穿透` must preserve ignore mode:
  - `关穿透` only clears `SKL` and one-shot penetrate cleanup state.
  - It must not call `stopIgnoreCaptureLoop()`.
  - It must not set `PIXEL_SIZEBack8` back to 255 while `shouldRun == true`.
- The one-shot clean-frame gate only opens `PIXEL_SIZEBack8` temporarily when ignore is not already running, then restores it immediately after the frame write.
- Quick `关穿透 -> 开穿透` toggles clear any stale one-shot marker before starting penetrate rendering.

### Guardrails
- Do not replace the one-shot clean-frame logic with a plain `video_service::refresh()` only; static Android screens may not produce a new frame.
- Do not let penetrate close reset `shouldRun`, `pendingIgnoreCapture`, or user-requested ignore state.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-10] CloudSend status monitor synchronization fix — 2026-05-08

### Status Panel Correctness
- Fixed first-connection status flicker: Android now pushes one `cloudsend_status` packet immediately after authorization, instead of waiting for the next 1s timer tick.
- Changed `CloudSendStatusData` fields to nullable booleans so the monitor can render an explicit waiting state (`—`) instead of showing all-red false defaults before the first packet arrives.
- Added a 5s stale-status watchdog in `CloudSendStatusModel`; if status packets stop arriving, the panel resets to waiting state instead of keeping misleading old values.
- Reset the monitor on manual reconnect, Android auto-reconnect, and session close.

### Android Status Semantics
- Added `@Volatile` visibility protection for cross-thread Android status fields: `SKL`, `BIS`, `_isReady`, `_isStart`, `_isAudioStart`, `mediaProjection`, and AccessibilityService `ctx`.
- `cloudsend_status` now snapshots Android values before building JSON to avoid mixed-state reads.
- Split status meanings:
  - `screenshot`: special screenshot stream is actually running (`shouldRun && accessibility`).
  - `ignore`: ignore switch is logically on (`shouldRun || pendingIgnoreCapture`), including pending wait for accessibility.
- Added `nZW99cdXQ0COhB2o.isIgnorePending` for status aggregation.
- Kept the UI label "加密状态" unchanged; it still means Android accessibility service connection state.

### Guardrails
- Do not restore false-default status UI for the monitor; `null` means waiting/unknown and must render gray.
- Do not collapse `screenshot` and `ignore` back to the same source; they intentionally represent actual running stream vs requested switch state.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-9] CloudSend final residual cleanup — 2026-05-06

### Cleanup
- Renamed Android build environment variables from `RUSTDESK_*` to `CLOUDSEND_*` in `env.sh` and `build.sh`, while intentionally keeping the `/opt/rustdesk-toolchain` path and existing signing file locations.
- Replaced remaining desktop UI labels with `CloudSend`, including the desktop tab title and desktop settings About card.
- Renamed login provider sentinel value from `daxian` to `cloudsend`.
- Renamed internal string values: clipboard owner UTI, printer temp file prefix, heartbeat public-domain check, plugin callback target, plugin local data directory segment, and debug close log.
- Removed obsolete `migrate_package.sh`.

### Manual action required
- Existing Linux signing/profile files must be migrated by the user, not Codex:
  `RUSTDESK_ANDROID_* -> CLOUDSEND_ANDROID_*` in signing.env and
  `RUSTDESK_TOOLCHAIN_ROOT -> CLOUDSEND_TOOLCHAIN_ROOT` in `/etc/profile.d/rustdesk-toolchain.sh`.

### Guardrails
- Keep `/opt/rustdesk-toolchain`, `/etc/profile.d/rustdesk-toolchain.sh`, existing keystore filename, and existing keystore alias unless the build environment is intentionally rebuilt.
- No build, clean, server-side sed, or git commit was executed by Codex.

## [v5.2.1-hotfix-8] PC CloudSend DLL / portable startup fix — 2026-05-05

### P0: Fix Windows startup after CloudSend rename
- Fixed Windows Dart FFI loading: `native_model.dart` now opens `cloudsend.dll` instead of `librustdesk.dll`.
- Kept Linux Dart FFI naming aligned with the renamed Rust library by opening `libcloudsend.so`.
- Updated portable packer defaults from `rustdesk.exe` to `cloudsend.exe`.
- The portable extractor now renames both legacy `rustdesk.exe` and current `cloudsend.exe` to `CloudSend.exe`, and falls back to the packaged executable path if the renamed file is unavailable.
- Renamed the portable app-name runtime environment key from `RUSTDESK_APPNAME` to `CLOUDSEND_APPNAME` across the packer, Rust core, and Flutter constant.
- Updated Windows portable build output names from `rustdesk_portable.exe` / `rustdesk-{version}-install.exe` to `cloudsend_portable.exe` / `cloudsend-{version}-install.exe`.
- Renamed the privacy-mode RuntimeBroker helper from `RuntimeBroker_rustdesk.exe` to `RuntimeBroker_cloudsend.exe` across portable packaging, runtime privacy mode, and MSI cleanup.
- Renamed Android wake-lock tags from `daxian:*` to `cloudsend:*`.
- Renamed the Windows app-name export from `get_rustdesk_app_name` to `get_cloudsend_app_name` and synchronized the runner lookup.

### Root cause
- Part 4 changed the Windows Rust cdylib output to `cloudsend.dll`, and `flutter/windows/CMakeLists.txt` installs `cloudsend.dll`.
- The Flutter runtime still tried to open `librustdesk.dll`, causing FFI initialization failure and a white-screen startup.
- The self-extracting portable wrapper still had old `rustdesk.exe` defaults, making the extracted startup path fragile after the executable rename.

### Guardrails
- Windows Flutter builds must keep these three names aligned: `flutter/windows/CMakeLists.txt` installs `cloudsend.dll`, `flutter/windows/runner/main.cpp` loads `cloudsend.dll`, and `flutter/lib/models/native_model.dart` opens `cloudsend.dll`.
- Portable packages should use `cloudsend.exe` as the metadata startup executable and may normalize the extracted visible executable to `CloudSend.exe`.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-7] CloudSend identity migration Parts 1-4 — 2026-05-05

### Branding / Android identity
- Android package changed from `com.daxian.dev` to `com.cloudsend.app`.
- Android visible app label and notification title changed to `CloudSend` at this stage; current Android visible label is superseded to `云计划` by `v5.2.1-docsync-13`.
- Android deep link scheme changed to `cloudsend://`.
- Kotlin package directory changed to `flutter/android/app/src/main/kotlin/com/cloudsend/app/`.

### Rust runtime / protocol / Flutter UI
- Rust `APP_NAME` changed to `CloudSend`.
- Version check type values changed to `cloudsend-client` / `cloudsend-server`; RustDesk public version URL was disabled with `https://127.0.0.1/version/latest`.
- Android status protocol field renamed from `daxian_status` to `cloudsend_status` while keeping field number 39.
- Flutter event renamed to `update_cloudsend_status`; model/widget renamed to `CloudSendStatusModel` / `CloudSendStatusMonitor`.
- Session option renamed to `show_cloudsend_status_monitor` / `show-cloudsend-status-monitor`.
- Virtual display platform addition key renamed to `cloudsend_virtual_displays`.

### Android SO / FFI
- Cargo crate renamed to `cloudsend`; `[lib] name = "cloudsend"` now builds `libcloudsend.so`.
- Android build script copies `target/<target>/release/libcloudsend.so` to `flutter/android/app/src/main/jniLibs/<abi>/libcloudsend.so`.
- Kotlin now uses `System.loadLibrary("cloudsend")`.
- Dart Android FFI now opens `libcloudsend.so`.
- Exported FFI symbols changed from `rustdesk_core_main*` to `cloudsend_core_main*` and generated bridge lookup strings were synchronized.

### Guardrails
- Do not revive `com.daxian.dev`, `daxian_status`, `DaxianStatusModel`, `libdaxian.so`, or `rustdesk_core_main` in new Android work.
- `Cargo.lock` was intentionally not edited by Codex; it should update when the user builds.
- No build, clean, or git commit was executed by Codex.

## [v5.2.1-hotfix-6] 无障碍权限感知的双通道控制 — 2026-04-17

### 核心特性

- PC 以 Android 无障碍（网络加密）服务状态为权威，动态决定是否启用双通道
- 无障碍未开或状态未知时，PC 只刷新/等待视频流，不发送"开无视"命令
- 无障碍已开时，PC 才允许视频流丢失 fallback 到截屏流
- 支持运行时动态切换：`cloudsend_status` 每秒同步 `accessibility` 字段
- 监测面板新增"加密状态"行

### 实现方式

- `DFm8Y8iMScvB2YDw.kt`: `cloudsend_status` JSON 增加 `accessibility`
- `model.dart`: `CloudSendStatusData.accessibility` 使用 `bool?`，`null` 表示尚未收到状态推送
- `model.dart`: 新增 `_canRequestAndroidBackupFrame`，作为所有自动"开无视"命令的守卫
- `model.dart`: 首帧 3s/10s fallback 在无障碍未知或未开时只执行 `sessionRefreshVideo`
- `overlay.dart`: 安卓状态监测显示"加密状态"

## [v5.2.1-hotfix-5] 修复 "开共享后一直卡在截屏流" 深度状态管理问题 — 2026-04-15

### P0: 状态残留 Bug 修复

- 修复用户取消 MediaProjection 授权后 Flutter `_isStart` 不回滚导致后续状态错乱
- 修复停服务再开服务时 `SKL` / `PIXEL_SIZEBack8` / `savedMediaProjectionIntent` / 黑屏 / 防触等状态残留
- 修复 `startCapture()` 启动前未强制清除三模式互斥状态，导致视频帧可能被 `SKL || shouldRun` 早退逻辑丢弃
- 修复 PC 端首帧 fallback 与 Android 授权流程的时序竞争：首次自动开无视从 500ms 延长到 3000ms

### 代码改动

- `nZW99cdXQ0COhB2o.kt`: 新增 `resetCaptureStates()`，统一清理 `shouldRun` / `SKL`
- `DFm8Y8iMScvB2YDw.kt`: `startCapture()` 开头强制重置；`destroy()` 补齐静态变量、黑屏、防触、token 清理
- `XerQvgpGBzr8FDFr.kt`: 授权失败时主动通知 Flutter `on_media_projection_canceled`
- `server_model.dart`: 新增 `onMediaProjectionDenied()` 回滚方法
- `server_page.dart`: 授权失败回调改为回滚服务状态
- `model.dart`: 首帧 fallback 延迟 500ms -> 3000ms

### 不受影响的功能

- 侧按钮协议和命令链路不变
- 画面传输协议、网络连接、安卓状态监测面板不变
- 黑屏、穿透、无视、防触功能本身不变，仅在关闭服务/启动共享时清理残留状态

## [v5.2.1-hotfix-4] 新增安卓状态监测面板 — 2026-04-17

### 功能新增

- PC 端右上角新增"安卓状态监测"面板，位于"显示质量监测"下方
- 显示 7 项 Android 被控端状态：视频/截屏/共享/无视/黑屏/穿透/防触
- "存在/开"绿色加粗，"丢失/关"红色加粗，标签灰色
- "显示设置"菜单新增"显示安卓状态监测"选项，默认开启
- 状态源：Android 端每秒 JSON 推送，延迟 <= 1 秒

### 协议变更

- `Misc` 消息新增 field 39: `string cloudsend_status`，proto3 向后兼容
- `InvokeUiSession` trait 新增 `update_cloudsend_status(json: String)` 方法
- 新增会话配置 `show_cloudsend_status_monitor`，toolbar 使用 `show-cloudsend-status-monitor`

### 涉及文件

- `libs/hbb_common/protos/message.proto`, `libs/hbb_common/src/config.rs`
- `src/client.rs`, `src/ui_session_interface.rs`, `src/flutter.rs`, `src/ui/remote.rs`
- `src/server/connection.rs`, `src/client/io_loop.rs`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/DFm8Y8iMScvB2YDw.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`
- `flutter/lib/consts.dart`, `flutter/lib/common/widgets/setting_widgets.dart`, `flutter/lib/common/widgets/toolbar.dart`
- `flutter/lib/models/model.dart`, `flutter/lib/common/widgets/overlay.dart`
- `flutter/lib/desktop/pages/remote_page.dart`, `flutter/lib/desktop/pages/view_camera_page.dart`
- `flutter/lib/mobile/pages/remote_page.dart`, `flutter/lib/mobile/pages/view_camera_page.dart`

## [v5.2.1-hotfix-3] 新增开防触/关防触侧按钮 — 2026-04-16

### 功能新增

- 新增"开防触"和"关防触"两个侧按钮（蓝开红关，放在开/关穿透之后）
- 采用时序自适应策略：空闲时吸收本地触摸，远程事件活跃期短暂切换为穿透
- 新增 `MOUSE_TYPE_TOUCHBLOCK=11`，对应 `mask=43`，URL 前缀 `TouchBlock_Management`
- 新增 JNI 命令 `touch_block`，由 MainService 路由到 `AccessibilityService.setTouchBlockEnabled`
- 新增独立的透明 `touchBlockOverlay`，与黑屏 overlay 完全隔离，互不干扰
- watchdog 100ms 间隔，仅在状态转换时触发 `updateViewLayout`，IPC 开销最小化

### UI 修复

- 修复 PC 端点击"适应屏幕大小"后侧按钮随画面 scale 过度放大、显示不完整的问题
- 侧按钮 overlay 现在按 11 行真实高度计算可用空间，并在需要时自动限制 scale
- 位置修正 `tryAdjust` 使用侧按钮真实总高度，避免按钮组被屏幕底部裁切

### 已知局限（Android 系统限制，非 bug）

- 首次远程事件在 flag 切换到位前可能被吸收（概率极低）
- PC 活跃控制期间本地用户硬触摸可能穿透
- 完美拦截需设备管理员或 root，标准 APK 无法实现

### 涉及文件

- `src/common.rs`, `src/flutter_ffi.rs`
- `libs/scrap/src/android/pkg2230.rs`, `libs/scrap/src/android/ffi.rs`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/DFm8Y8iMScvB2YDw.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`
- `flutter/lib/models/input_model.dart`
- `flutter/lib/common.dart`
- `flutter/lib/common/widgets/overlay.dart`

## [v5.2.1-hotfix-2] 开黑屏防触摸 Bug 修复 — 2026-04-14

### P0: 移除错误的动态 FLAG_NOT_TOUCHABLE 切换逻辑

- 删除 `isBlackScreenActive` / `restoreBlockRunnable` / `setOverlayTouchBlock` 三件套
- `onMouseInput` 入口不再向主线程 `handler` 提交任务，高频远程输入不再阻塞主线程
- `onstart_overlay` 和 50ms 轮询 `runnable` 只同步 `overlay.visibility`，不再操作 flags
- `onDestroy` 同步移除已删除的 `restoreBlockRunnable` 引用
- 根本原因：防触摸逻辑 FLAG 语义反转 + 每帧 `updateViewLayout` + 50ms 轮询三重问题
- 正确机制：远程输入使用 `AccessibilityService.dispatchGesture`，不经过 overlay，无需动态切换 flag
- 文件: `nZW99cdXQ0COhB2o.kt`
