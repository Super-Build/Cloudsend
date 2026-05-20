# CloudSend ADB/LADB Integration Memory

Generated: 2026-05-20
Last synchronized with source: 2026-05-21

This document is the engineering memory for the CloudSend ADB integration. It is based on the current CloudSend source tree, the local `ADB-CODE/` source tree, and the local `LADB/` source tree.

This document is now both the implementation memory and source-of-truth risk boundary for the ADB work that has landed in the source tree.

## 1. Current Decision

ADB capability is implemented in CloudSend as an isolated Android-side module.

Do not put ADB logic directly into the existing screen-share, ignore-capture, penetrate, blank-screen, touch-block, video stream, screenshot stream, or monitor-panel core paths.

Recommended direction:

- Keep the CloudSend Android ADB module isolated; do not add a second app.
- Continue to reuse LADB's local `adb` execution model.
- Reuse ADB-CODE's accessibility-assisted wireless-debugging automation ideas only in a later automation phase.
- Keep the existing CloudSend accessibility service as the only accessibility service.
- Add a narrow bridge between the existing accessibility service and a future ADB automation controller.
- Keep future PC remote ADB commands behind an explicit protocol, status model, whitelist, timeout, and audit log.
- Never reuse existing side-button masks for ADB commands.

Key limitation:

- Android 11+ is the primary target for no-PC wireless debugging pairing.
- Android 9/10 do not have the standard Android wireless-debugging pairing-code flow.
- Domestic ROMs can rename or move Developer Options and Wireless Debugging pages. Accessibility automation must be best-effort, cancellable, timeout-protected, and user-visible.
- Built-in ADB plus accessibility plus remote command execution is a high-sensitivity capability. It must be explicit, optional, and auditable.

Current landed scope:

- Android local ADB pairing, mDNS scan, connect, shell, command input, output terminal, and limited shell-restart recovery are implemented.
- Accessibility-assisted automatic wireless-debugging setup is not implemented yet; the `Open debugging` button remains a placeholder.
- PC remote ADB command protocol is not implemented yet.
- ADB is not required for screen sharing and does not participate in side-button or video/screenshot stream state.

## 2. Current CloudSend State

### 2.1 Mobile Home Pages

Current files:

- `flutter/lib/mobile/pages/home_page.dart`
- `flutter/lib/mobile/pages/server_page.dart`
- `flutter/lib/mobile/pages/adb_page.dart`

Current facts:

- Android mobile home now uses a `PageView`.
- The only active pages are:
  - `ServerPage()` for the screen-share page.
  - `AdbPage()` for the ADB page.
- The bottom navigation bar remains commented out.
- `ConnectionPage` remains inside `if (false)` and is not active.
- `SettingsPage` remains commented out and is not active.
- The ADB page is now interactive and calls the isolated CloudSend ADB MethodChannel methods only when the user taps ADB controls.

Current ADB page UI:

- First card title: `ADB`.
- First card has explanatory text above a full-width button. The displayed Chinese label is represented in source as `\u542f\u52a8\u670d\u52a1` (`Start service`).
- Tapping the first-card button opens a pairing dialog and then starts/pairs the bundled ADB runner through MethodChannel.
- Second card title is represented in source as `\u81ea\u52a8\u5316\u65e0\u7ebf\u8c03\u8bd5` (`Automated wireless debugging`).
- Second card has explanatory text above a full-width placeholder button. The displayed Chinese label is represented in source as `\u6253\u5f00\u8c03\u8bd5` (`Open debugging`).
- The automated wireless-debugging button is still a placeholder and has an empty callback.
- The ADB page does not call `serverModel`, `toggleService`, screen-share service methods, side-button methods, or Rust connection logic.

### 2.1.1 ADB Environment and Runtime Added on 2026-05-20/2026-05-21

Implemented ADB integration:

- Added `libadb.so` from local LADB into CloudSend Android `jniLibs` for:
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86_64`
- Added `flutter/android/app/src/main/jniLibs/LIBADB_LICENSE`.
- Added Gradle `packagingOptions.jniLibs.useLegacyPackaging = true` so `libadb.so` can be extracted to `applicationInfo.nativeLibraryDir`.
- Do not add Gradle `ndk.abiFilters` here: Flutter `--split-per-abi` already sets split ABI filters, and both configurations conflict.
- Added Manifest permission `CHANGE_WIFI_MULTICAST_STATE`.
- Added Manifest permission `CHANGE_WIFI_STATE` to match the LADB wireless-debugging environment baseline.
- Added Manifest declaration for `WRITE_SECURE_SETTINGS` with `tools:ignore="ProtectedPermissions"`.
- Added isolated Kotlin package:
  - `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbState.kt`
  - `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbRunner.kt`
  - `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbManager.kt`
  - `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbDnsDiscover.kt`
- `CloudSendAdbState` records support/binary/initialization/pairing/paired/connected/shell-ready/output/error state, the extracted `adbPath`, whether the binary exists, whether it is executable, and the ProcessBuilder environment map (`HOME` and `TMPDIR`).
- Added safe Flutter MethodChannel hooks on the existing Android channel:
  - `cloudsend_adb_init`: initializes the isolated ADB environment state and returns a map.
  - `cloudsend_adb_status`: returns the current ADB environment state map.
  - `cloudsend_adb_output`: returns the bounded terminal output buffer.
  - `cloudsend_adb_start`: starts the LADB-style ADB scan/connect/shell flow.
  - `cloudsend_adb_local_shell`: starts the non-ADB local shell flow used when the user chooses `Skip`.
  - `cloudsend_adb_pair`: runs `adb pair localhost:<port>` with the supplied pairing code.
  - `cloudsend_adb_command`: writes user input into the current shell process.
- Added Flutter constants in `AndroidChannel`:
  - `AndroidChannel.kCloudSendAdbInit`
  - `AndroidChannel.kCloudSendAdbStatus`
  - `AndroidChannel.kCloudSendAdbOutput`
  - `AndroidChannel.kCloudSendAdbStart`
  - `AndroidChannel.kCloudSendAdbLocalShell`
  - `AndroidChannel.kCloudSendAdbPair`
  - `AndroidChannel.kCloudSendAdbCommand`
- Added Flutter helper `AndroidAdbManager` in `flutter/lib/common.dart`.
- Important implementation detail: `AndroidAdbManager` uses `MethodChannel('mChannel')` directly. Do not route ADB methods through `gFFI.invokeMethod()`, because `FFI.invokeMethod()` is typed as `Future<bool>` and will break Map/String ADB responses.
- Added interactive ADB page wiring:
  - Tapping the ADB page `Start service` button opens a pairing dialog.
  - The pairing dialog has pairing port and pairing-code inputs plus `Skip` and `Pair` actions.
  - The terminal card shows a clipped top progress bar while waiting/starting/pairing and polls native ADB output every 100 ms.
  - A command input card exists under the terminal and is enabled only after the ADB shell is ready.
- Added ProGuard keep rule for `com.cloudsend.app.adb.**`.

Current runtime behavior:

- No ADB process is started automatically when opening the page.
- ADB start/pair/command actions only run after the user taps the ADB page controls.
- First successful manual pairing saves `paired_before` in `SharedPreferences`.
- If `paired_before` is true, tapping `Start service` skips the pairing dialog and automatically starts the scan/connect/shell flow. If auto-start fails, the UI falls back to the pairing dialog.
- `Skip` starts a non-ADB local shell (`sh -l`) and must not claim ADB is connected.
- `Pair` runs `adb pair localhost:<port>` with a LADB-style pairing-code delay, then starts the ADB server/scan/connect/shell flow when pairing succeeds.
- The runner uses LADB-style mDNS connect-port discovery via `CloudSendAdbDnsDiscover`, scanning `_adb-tls-connect._tcp`.
- When a connect port is found, it runs `adb connect localhost:<port>`.
- When no connect port is found, it uses LADB's `adb wait-for-device` fallback.
- It parses `adb devices`, chooses a local device (`localhost:` / `127.0.0.1:`) first when multiple devices are present, and then opens `adb shell`.
- On shell entry it injects `alias adb="<nativeLibraryDir>/libadb.so"`.
- On ADB shell entry it requests `WRITE_SECURE_SETTINGS` using `pm grant <package> android.permission.WRITE_SECURE_SETTINGS` and prints `ADB permission grant requested` and `ADB shell ready`.
- If `WRITE_SECURE_SETTINGS` is already granted, startup follows LADB's helper logic: disables `mobile_data_always_on` when needed and cycles `adb_wifi_enabled` to refresh wireless-debugging broadcasts.
- Shell death restarts after 3 seconds, but CloudSend limits this to 3 attempts to avoid infinite restart loops.
- Terminal output is bounded to 16 KB.
- Existing screen-share and side-button paths are untouched.
- Location permissions from LADB are intentionally not added. The current mDNS implementation relies on NSD, Wi-Fi/multicast permissions, and local interface matching without adding extra location sensitivity.

### 2.2 Existing Android Runtime Core

Important files:

- `flutter/android/app/src/main/kotlin/com/cloudsend/app/DFm8Y8iMScvB2YDw.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`
- `flutter/android/app/src/main/kotlin/pkg2230.kt`
- `flutter/android/app/src/main/kotlin/ffi.kt`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`

Current monitor-panel behavior:

- Android builds `cloudsend_status` JSON in MainService.
- Rust queries it through `call_main_service_get_by_name("cloudsend_status")`.
- Invalid or unavailable Android status must not be converted to hardcoded false JSON.
- Dart monitor state must keep null or waiting state when no valid status is available.
- ADB status can be added later, but existing 8 monitor fields must not change meaning.

### 2.3 Existing Accessibility Service

Important file:

- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`

Current responsibility:

- Input control.
- Ignore-capture screenshot flow.
- Penetrate drawing support.
- Blank-screen and touch-block state support.
- Accessibility availability status.

ADB integration rule:

- Do not create a second accessibility service.
- Do not permanently run ADB automation inside every accessibility event.
- Add an explicit ADB automation controller that is active only during ADB pairing/setup.
- Existing accessibility behavior must keep priority and must not be broken by ADB automation.

## 3. LADB Source Review

Local path:

- `LADB/`

### 3.1 LADB Purpose

LADB is a local ADB shell app for Android.

Its README explains the core idea: it bundles an ADB server/client binary inside app libraries, then uses Android Wireless Debugging so the bundled ADB process can connect to the same local device.

LADB is not using a normal Android SDK API to gain ADB power. It runs a packaged `adb` binary with `ProcessBuilder`.

### 3.2 Key LADB Files

Reviewed files:

- `LADB/README.md`
- `LADB/app/build.gradle`
- `LADB/app/src/main/AndroidManifest.xml`
- `LADB/app/src/main/java/com/draco/ladb/utils/ADB.kt`
- `LADB/app/src/main/java/com/draco/ladb/utils/DnsDiscover.kt`
- `LADB/app/src/main/java/com/draco/ladb/viewmodels/MainActivityViewModel.kt`
- `LADB/app/src/main/java/com/draco/ladb/views/MainActivity.kt`
- `LADB/app/src/main/res/layout/activity_main.xml`
- `LADB/app/src/main/res/layout/dialog_pair.xml`
- `LADB/app/src/main/res/values/strings.xml`
- `LADB/app/src/main/jniLibs/*/libadb.so`

### 3.3 Build and Packaging Facts

LADB build facts:

- `compileSdk 35`
- `targetSdk 35`
- `minSdk 26`
- `versionName 2.5.6`
- Kotlin Android app.
- Uses coroutines, lifecycle ViewModel, appcompat, preference, material components.
- Has `jniLibs.useLegacyPackaging = true`.
- Ships `libadb.so` for:
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86`
  - `x86_64`

CloudSend current Android build facts:

- `compileSdkVersion 34`
- `targetSdkVersion 33`
- `minSdkVersion 21`
- Application ID: `com.cloudsend.app`
- Current Android build script primarily packages `libcloudsend.so` and `libc++_shared.so`.

Integration implication:

- If CloudSend runs packaged `libadb.so` through `ProcessBuilder`, the native library must be extractable at runtime.
- CloudSend has Android Gradle `jniLibs.useLegacyPackaging = true` enabled for extractable `libadb.so`.
- ABI coverage must match CloudSend build outputs. The Android build script currently supports arm64, armv7, x86_64, and has helper paths for x86.

### 3.4 `ADB.kt` Behavior

Core LADB mechanism:

- `adbPath = "${context.applicationInfo.nativeLibraryDir}/libadb.so"`
- `scriptPath = "${context.getExternalFilesDir(null)}/script.sh"`
- Runs commands through `ProcessBuilder`.
- Sets:
  - `HOME = context.filesDir.path`
  - `TMPDIR = context.cacheDir.path`
- Uses one long-lived shell process for command input.
- Redirects shell output to a temp file.
- Has LiveData fields for `running` and `closed`.

Important methods:

- `initServer()`
- `pair(port, pairingCode)`
- `getDevices()`
- `sendToShellProcess(msg)`
- `waitForDeathAndReset()`
- `cycleWirelessDebugging()`
- `disableMobileDataAlwaysOn()`

Important behavior:

- If `WRITE_SECURE_SETTINGS` is granted, LADB can toggle `adb_wifi_enabled`.
- If Android 11+ wireless debugging is not enabled, it waits until the user enables it.
- It waits for mDNS scan to discover a connect port.
- It runs `adb start-server`.
- It runs `adb connect localhost:<port>` when a port is found.
- It falls back to `adb wait-for-device` when no port is found.
- It opens `adb shell`.
- It attempts `pm grant <package> android.permission.WRITE_SECURE_SETTINGS` from the shell when permission is not already granted.

CloudSend reuse:

- Reuse the packaged `adb` ProcessBuilder model.
- Reuse `pair(port, code)` stdin handling.
- Reuse environment setup (`HOME`, `TMPDIR`).
- Reuse output truncation concepts.
- Rework shell lifecycle to avoid uncontrolled infinite restart loops.

CloudSend must not copy as-is:

- A permanent interactive raw shell open to PC.
- Infinite `waitForDeathAndReset()` restart behavior.
- UI-bound LiveData as the primary architecture.
- LADB package names or Activity structure.

### 3.5 `DnsDiscover.kt` Behavior

LADB discovers the wireless-debugging connect port using Android NSD:

- Service type: `_adb-tls-connect._tcp`
- API: `NsdManager.discoverServices(...)`
- Resolves services with `NsdManager.ResolveListener`.
- Filters resolved services by comparing resolved host with the device Wi-Fi IPv4 address.
- Chooses the best port using TXT expiration time or service name ordering.
- Exposes:
  - `adbPort`
  - `pendingResolves`
  - `aliveTime`

CloudSend reuse:

- Use mDNS discovery for the wireless-debugging connect port.
- Add timeout and cancellation.
- Add failure reason reporting.

Manifest implication:

- CloudSend already has `ACCESS_WIFI_STATE` and `ACCESS_NETWORK_STATE`.
- CloudSend now declares `CHANGE_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE` for the ADB wireless-debugging environment baseline.
- Location permission requirements for NSD/mDNS can vary by Android version and OEM behavior. Keep this behind a user-visible setup flow.

### 3.6 `MainActivityViewModel.kt` and `MainActivity.kt`

LADB UI model:

- `MainActivityViewModel` owns `ADB` and `DnsDiscover`.
- It starts output polling.
- It starts mDNS scan in init.
- It starts ADB in IO coroutine.
- It stores a `paired` flag in SharedPreferences.
- `MainActivity` shows pairing dialog when needed.
- `MainActivity` provides a terminal-like command input and output view.

CloudSend reuse:

- Keep state separate from UI.
- Store paired state.
- Provide manual pairing fallback.
- Provide status text and last error.

CloudSend must not copy directly:

- Terminal-first UI.
- Full bookmark/help/piracy-check features.
- Activity restart/exit behavior.

## 4. ADB-CODE Source Review

Local path:

- `ADB-CODE/`

Existing analysis file:

- `ADB-CODE/PROJECT_ANALYSIS.md`

ADB-CODE is a broader experimental project. It uses accessibility automation to open Developer Options, Wireless Debugging, pairing-code screens, and then uses local ADB mechanisms to grant sensitive permissions or maintain state.

Useful parts:

- Accessibility state machine ideas.
- OEM settings-page keyword lists.
- Pairing code and port extraction heuristics.
- Manual fallback flow.
- Logging style and timeout ideas.

High-risk parts that should not be merged into CloudSend mainline:

- Long-running daemon in `/data/local/tmp`.
- HTTP `/exec` API.
- Boot helper.
- Watchdog that repeatedly grants permissions or re-enables wireless debugging.
- Silent self-recovery of sensitive permissions.

## 5. Recommended CloudSend ADB Architecture

### 5.1 Android Kotlin Module

Recommended new package:

```text
flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/
```

Current and planned classes:

```text
CloudSendAdbManager.kt
CloudSendAdbState.kt
CloudSendAdbRunner.kt
CloudSendAdbDnsDiscover.kt
CloudSendAdbAutomationController.kt (future)
CloudSendAdbCommandPolicy.kt (future)
```

Responsibilities:

- `CloudSendAdbManager`: public facade used by Flutter MethodChannel and Rust/JNI status calls.
- `CloudSendAdbState`: immutable state snapshot for UI/monitor.
- `CloudSendAdbRunner`: ProcessBuilder wrapper around `libadb.so`; owns pair/start/connect/shell/command/output/restart state.
- `CloudSendAdbDnsDiscover`: mDNS discovery for `_adb-tls-connect._tcp`.
- Pairing memory is currently stored inside `CloudSendAdbManager` using `SharedPreferences` key `paired_before`.
- `CloudSendAdbAutomationController`: future short-lived accessibility automation state machine.
- `CloudSendAdbCommandPolicy`: future whitelist and command validation for any future PC-side ADB commands.

### 5.2 Flutter ADB Page

Current ADB page:

- `flutter/lib/mobile/pages/adb_page.dart`

Implemented UI behavior:

1. `Start service` initializes ADB state.
2. If `paired_before` is true, it starts ADB scan/connect automatically.
3. Otherwise it opens a manual pairing dialog with port/code inputs.
4. `Pair` runs real `adb pair` and then starts scan/connect/shell on success.
5. `Skip` enters non-ADB local shell mode.
6. The terminal card shows progress while pairing/starting and streams native output.
7. The command input card is enabled only when `shellReady == true`.

Still pending:

- Explicit stop/reset button.
- Separate visual status chips for supported/paired/connected/shell-ready.
- Accessibility-assisted wireless-debugging automation in the `Open debugging` placeholder card.
- PC remote command UI/protocol.

Do not add PC-side remote command execution UI before Android local ADB remains stable across test devices.

### 5.3 Status Integration

Existing ADB state map fields:

```json
{
  "supported": true,
  "binaryAvailable": true,
  "binaryExecutable": true,
  "initialized": true,
  "pairing": false,
  "paired": true,
  "connected": true,
  "shellReady": true,
  "output": "...",
  "adbPath": ".../libadb.so",
  "environment": {
    "HOME": ".../files",
    "TMPDIR": ".../cache"
  },
  "lastError": ""
}
```

Rules:

- Existing 8 monitor-panel fields must remain unchanged.
- ADB status failure must not make existing screen-share status red.
- Missing ADB status should remain null/waiting, not false.
- ADB status updates should be independent from side-button state.

### 5.4 PC Remote ADB Commands

PC remote ADB command support should be a later phase.

Required rules:

- New proto messages, not reused side-button masks.
- Request/response IDs.
- Timeout per request.
- Explicit Android-side authorization.
- Whitelist-first command policy.
- Output truncation.
- Audit log.
- Queue commands serially.
- Never expose a raw unlimited remote shell by default.

Suggested future proto names:

```text
CloudSendAdbRequest
CloudSendAdbResponse
```

Potential fields:

```text
request_id
command_key
args
timeout_ms
requires_android_confirmation
success
exit_code
stdout
stderr
error
duration_ms
```

## 6. Permissions and Packaging Checklist

CloudSend currently has:

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `SYSTEM_ALERT_WINDOW`
- `FOREGROUND_SERVICE`
- `MANAGE_EXTERNAL_STORAGE`
- Accessibility service declaration

ADB module additions now present:

- `CHANGE_WIFI_MULTICAST_STATE`
- `CHANGE_WIFI_STATE`
- `WRITE_SECURE_SETTINGS` declaration. Declaring it does not grant it.

ADB module additions still deferred:

- Possibly location permission for reliable NSD/mDNS behavior on some devices.

Native library packaging:

- `libadb.so` is already added for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Packaged `libadb.so` is configured to be extractable via `jniLibs.useLegacyPackaging = true`.
- `x86/libadb.so` is intentionally not included because the current Android build script does not build `libcloudsend.so` for x86.
- Avoid naming conflicts with `libcloudsend.so`.

## 7. Security and Product Risk

High-risk signals:

- Bundled ADB binary.
- Wireless debugging automation.
- Accessibility automation.
- `WRITE_SECURE_SETTINGS`.
- Remote command execution.

Mitigations:

- User-visible ADB page.
- Explicit setup button.
- Clear status display.
- Stop/reset control.
- Whitelist commands.
- No default raw shell to PC.
- No HTTP `/exec`.
- No daemon/watchdog.
- No silent long-term re-enable behavior.
- Logs bounded and user-visible.

## 8. Phased Plan

### Phase 1: UI and State Skeleton

Status: implemented.

Already done:

- Added ADB page in mobile home PageView.
- Added interactive ADB card with `Start service`.
- Added `Automated wireless debugging` card with placeholder `Open debugging`.
- Added terminal output card with bounded live output and clipped progress bar.
- Added command input card enabled only when `shellReady == true`.
- Added Flutter `AndroidAdbManager` wrapper and MethodChannel method names for init/status/output/start/local-shell/pair/command.

### Phase 2: Android ADB Module Skeleton

Status: implemented on 2026-05-20 / 2026-05-21.

Added:

- `CloudSendAdbState`
- `CloudSendAdbRunner`
- `CloudSendAdbManager`
- `CloudSendAdbDnsDiscover`
- `libadb.so` packaging environment
- Manifest/Gradle packaging prerequisites
- MethodChannel bridge in `oFtTiPzsqzBHGigp.kt`
- Runtime state publication to Flutter through `cloudsend_adb_status`
- Real local pair/connect/shell/command implementation

Required:

- No dependency on screen-share service lifecycle.
- No dependency on side buttons.
- No accessibility automation yet.
- Existing monitor-panel status is unchanged and independent from ADB state.

### Phase 3: LADB Runner Port

Status: implemented for local Android ADB.

Ported local adb runner essentials:

- ProcessBuilder execution wrapper: implemented for `start-server`, `pair`, `devices`, `shell`, and command forwarding.
- `adb pair`: implemented with the LADB-style pairing-code delay.
- `adb connect`: implemented through `CloudSendAdbDnsDiscover`, which scans `_adb-tls-connect._tcp`, waits briefly for newer broadcasts, and runs `adb connect localhost:<port>`.
- `adb wait-for-device`: used as fallback when no mDNS connect port is discovered.
- `adb devices`: parsed to choose a connected local device.
- `adb shell` or one-shot command execution: shell opening is implemented once a device is connected; command input is enabled only when `shellReady` is true.
- Non-ADB local shell: implemented for the `Skip` path.
- Bounded output: implemented with an in-memory 16 KB output buffer.
- Timeout: implemented for pairing and command execution paths.
- Restart guard: shell restart is capped to avoid uncontrolled infinite reconnect loops.
- Startup shell commands: injects an `adb` alias and requests `WRITE_SECURE_SETTINGS` grant from the ADB shell when available.

Still pending:

- Explicit stop/reset UI.
- Optional startup-command setting.
- PC remote ADB command protocol.

Do not port LADB UI.

### Phase 4: mDNS Discovery

Status: implemented.

Implemented:

- Android NSD scan for `_adb-tls-connect._tcp`.
- MulticastLock during discovery.
- Timeout and safe cleanup.
- Local-IP aware filtering where possible.
- Newest-service preference using TXT expiration/name heuristics.
- Terminal-visible discovery logs and failure fallback.

Still pending:

- Only consider additional permissions, such as location, if real-device testing proves an OEM requires it. Do not add sensitive permissions preemptively.

### Phase 5: Manual Pairing Fallback

Status: implemented.

Implemented UI:

- Pairing port.
- Pairing code.
- Connect status.
- Last error.
- `Pair` runs real `adb pair`; success stores `paired_before` and starts the scan/connect/shell flow.
- `Skip` enters non-ADB local shell mode, not fake ADB mode.
- If `paired_before` auto-start fails, the UI falls back to the pairing dialog.

### Phase 6: Accessibility-Assisted Wireless Debugging

Status: not implemented.

Use ADB-CODE as reference, but rewrite for CloudSend:

- Open Developer Options / Wireless Debugging.
- Click pair button.
- Extract pairing port/code.
- Pass result to CloudSend ADB manager.
- Timeout and cancel safely.

### Phase 7: Monitor Panel Status

Status: deferred.

Requirement if implemented later:

- Prefer a separate ADB status path or clearly isolated fields.
- Existing 8 screen-share/side-button monitor fields must not regress.
- Missing ADB status must not turn existing screen-share status red.

### Phase 8: PC Remote ADB Commands

Status: deferred.

Only after Android local ADB is stable.

Start with safe whitelist commands.

## 9. Do Not Do

Do not:

- Copy LADB `MainActivity` into CloudSend.
- Add a second launcher Activity for ADB.
- Add a second accessibility service.
- Expose arbitrary `/exec`.
- Add a daemon or boot helper.
- Add infinite reconnect loops.
- Merge ADB state into side-button masks.
- Make ADB required for screen sharing.
- Break Android 9/10 normal screen-share behavior.
- Change current screen-share/ignore/penetrate/blank/touch-block logic while adding ADB.

## 10. Source References

CloudSend:

- `flutter/lib/mobile/pages/home_page.dart`
- `flutter/lib/mobile/pages/adb_page.dart`
- `flutter/lib/mobile/pages/server_page.dart`
- `flutter/lib/common.dart`
- `flutter/lib/consts.dart`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/oFtTiPzsqzBHGigp.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/DFm8Y8iMScvB2YDw.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbState.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbRunner.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbManager.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/CloudSendAdbDnsDiscover.kt`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`
- `flutter/android/app/build.gradle`
- `flutter/android/app/proguard-rules`
- `flutter/android/app/src/main/AndroidManifest.xml`
- `flutter/android/app/src/main/jniLibs/*/libadb.so`
- `build.sh`

Note:

- Current local Android ADB is implemented through Flutter MethodChannel plus Android Kotlin only.
- `src/server/connection.rs` and `libs/hbb_common/protos/message.proto` are listed because future PC remote ADB commands must use an explicit protocol path there; they are not part of the current local ADB command path.

LADB:

- `LADB/README.md`
- `LADB/app/build.gradle`
- `LADB/app/src/main/AndroidManifest.xml`
- `LADB/app/src/main/java/com/draco/ladb/utils/ADB.kt`
- `LADB/app/src/main/java/com/draco/ladb/utils/DnsDiscover.kt`
- `LADB/app/src/main/java/com/draco/ladb/viewmodels/MainActivityViewModel.kt`
- `LADB/app/src/main/java/com/draco/ladb/views/MainActivity.kt`
- `LADB/app/src/main/jniLibs/*/libadb.so`
- `LADB/LICENSE`
- `LADB/app/src/main/jniLibs/LICENSE`

ADB-CODE:

- `ADB-CODE/PROJECT_ANALYSIS.md`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/MainActivity.java`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/PairActivity.java`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/MyAccessibilityService.java`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/LocalAdbManager.java`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/NativeAdbWrapper.java`
- `ADB-CODE/AutoAccessibilityDemo/app/src/main/java/com/demo/accessibility/AccessibilityAutoEnabler.java`
- `ADB-CODE/adb_daemon/server.go`
- `ADB-CODE/adb_daemon/watchdog.go`

## 11. Current Baseline for Next Development

Use this document plus the current source tree as the baseline for the next coding phase.

Already implemented:

1. Android ADB state skeleton.
2. Flutter ADB page status binding.
3. LADB runner port.
4. Manual pair/connect.
5. mDNS connect discovery.

Still future/deferred:

1. Accessibility-assisted wireless-debugging setup.
2. Explicit ADB stop/reset UI.
3. Optional visual status chips for supported/paired/connected/shell-ready.
4. Optional ADB status integration, isolated from the existing 8 monitor-panel fields.
5. PC remote command protocol with authorization, whitelist, timeout, output truncation, and audit log.

Every phase must preserve:

- Android screen share.
- PC connection.
- Side buttons.
- Monitor panel.
- Video stream.
- Screenshot stream.
- Existing build scripts.
