# CloudSend ADB/LADB Integration Memory

Generated: 2026-05-20

This document is the engineering memory for the upcoming CloudSend ADB integration. It is based on the current CloudSend source tree, the local `ADB-CODE/` source tree, and the local `LADB/` source tree.

This is not an implementation patch. It is the source-of-truth plan and risk boundary before code changes begin.

## 1. Current Decision

ADB capability is feasible for CloudSend, but it must be integrated as an isolated Android-side module.

Do not put ADB logic directly into the existing screen-share, ignore-capture, penetrate, blank-screen, touch-block, video stream, screenshot stream, or monitor-panel core paths.

Recommended direction:

- Add a CloudSend Android ADB module, not a second app.
- Reuse LADB's local `adb` execution model.
- Reuse ADB-CODE's accessibility-assisted wireless-debugging automation ideas.
- Keep the existing CloudSend accessibility service as the only accessibility service.
- Add a narrow bridge between the existing accessibility service and a new ADB automation controller.
- Keep PC remote ADB commands behind an explicit protocol, status model, whitelist, timeout, and audit log.
- Never reuse existing side-button masks for ADB commands.

Key limitation:

- Android 11+ is the primary target for no-PC wireless debugging pairing.
- Android 9/10 do not have the standard Android wireless-debugging pairing-code flow.
- Domestic ROMs can rename or move Developer Options and Wireless Debugging pages. Accessibility automation must be best-effort, cancellable, timeout-protected, and user-visible.
- Built-in ADB plus accessibility plus remote command execution is a high-sensitivity capability. It must be explicit, optional, and auditable.

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
- The ADB page is currently UI-only.

Current ADB page UI:

- First card title: `ADB`.
- First card has explanatory text above a full-width placeholder button. The displayed Chinese label is represented in source as `\u542f\u52a8\u670d\u52a1` (`Start service`).
- Second card title is represented in source as `\u81ea\u52a8\u5316\u65e0\u7ebf\u8c03\u8bd5` (`Automated wireless debugging`).
- Second card has explanatory text above a full-width placeholder button. The displayed Chinese label is represented in source as `\u6253\u5f00\u8c03\u8bd5` (`Open debugging`).
- Both ADB page buttons currently use empty callbacks.
- The ADB page does not call `gFFI`, `bind`, `serverModel`, `toggleService`, or any Android method channel.

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
- CloudSend may need Android Gradle `jniLibs.useLegacyPackaging = true` or equivalent packaging behavior.
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
- CloudSend should consider adding `CHANGE_WIFI_MULTICAST_STATE` for more stable mDNS behavior on some ROMs.
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

Recommended classes:

```text
CloudSendAdbManager.kt
CloudSendAdbState.kt
CloudSendAdbRunner.kt
CloudSendAdbDnsDiscover.kt
CloudSendAdbPairingStore.kt
CloudSendAdbAutomationController.kt
CloudSendAdbCommandPolicy.kt
```

Suggested responsibilities:

- `CloudSendAdbManager`: public facade used by Flutter MethodChannel and Rust/JNI status calls.
- `CloudSendAdbState`: immutable state snapshot for UI/monitor.
- `CloudSendAdbRunner`: ProcessBuilder wrapper around `libadb.so`.
- `CloudSendAdbDnsDiscover`: mDNS discovery for `_adb-tls-connect._tcp`.
- `CloudSendAdbPairingStore`: SharedPreferences for paired flags and last known state.
- `CloudSendAdbAutomationController`: short-lived accessibility automation state machine.
- `CloudSendAdbCommandPolicy`: whitelist and command validation for any future PC-side ADB commands.

### 5.2 Flutter ADB Page

Current ADB page:

- `flutter/lib/mobile/pages/adb_page.dart`

Next UI milestones:

1. Show Android version support.
2. Show accessibility status.
3. Show wireless-debugging setup status.
4. Show ADB paired/connected status.
5. Add manual port/code fallback input.
6. Add setup log area.
7. Add explicit stop/reset button.

Do not add remote command execution UI before local pairing and status are stable.

### 5.3 Status Integration

Recommended status fields:

```json
{
  "adb_supported": true,
  "adb_accessibility_ready": true,
  "adb_wireless_debug_ready": false,
  "adb_pairing": false,
  "adb_paired": false,
  "adb_connected": false,
  "adb_shell_ready": false,
  "adb_last_error": ""
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

Likely ADB module additions:

- `CHANGE_WIFI_MULTICAST_STATE`
- Possibly location permission for reliable NSD/mDNS behavior on some devices.
- `WRITE_SECURE_SETTINGS` declaration only if the product decision accepts the sensitivity. Declaring it does not grant it.

Native library packaging:

- Add `libadb.so` for required ABIs only after deciding which Android APK variants should support ADB.
- Ensure packaged `libadb.so` is extractable and executable from `applicationInfo.nativeLibraryDir`.
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

Status: partially started.

Already done:

- Added ADB page in mobile home PageView.
- Added placeholder ADB card.
- Added placeholder `\u542f\u52a8\u670d\u52a1` (`Start service`) button.
- Added `\u81ea\u52a8\u5316\u65e0\u7ebf\u8c03\u8bd5` (`Automated wireless debugging`) card.
- Added placeholder `\u6253\u5f00\u8c03\u8bd5` (`Open debugging`) button.

Next:

- Add Flutter state model for ADB status.
- Add MethodChannel method names but keep them no-op until Kotlin module exists.

### Phase 2: Android ADB Module Skeleton

Add Kotlin package and no-op state manager.

Required:

- No dependency on screen-share service lifecycle.
- No dependency on side buttons.
- No accessibility automation yet.
- Status snapshot only.

### Phase 3: LADB Runner Port

Port only the local adb runner essentials:

- ProcessBuilder wrapper.
- `adb pair`.
- `adb connect`.
- `adb shell` or one-shot command execution.
- Bounded output.
- Timeout.
- Stop/reset.

Do not port LADB UI.

### Phase 4: mDNS Discovery

Port and adapt LADB `DnsDiscover`.

Add:

- Timeout.
- Cancellation.
- Failure reason.
- Permission checks.
- ROM compatibility notes.

### Phase 5: Manual Pairing Fallback

Add UI for:

- Pairing port.
- Pairing code.
- Connect status.
- Last error.

### Phase 6: Accessibility-Assisted Wireless Debugging

Use ADB-CODE as reference, but rewrite for CloudSend:

- Open Developer Options / Wireless Debugging.
- Click pair button.
- Extract pairing port/code.
- Pass result to CloudSend ADB manager.
- Timeout and cancel safely.

### Phase 7: Monitor Panel Status

Append ADB fields to status JSON or add a separate status path.

Requirement:

- Existing screen-share status must not regress.

### Phase 8: PC Remote ADB Commands

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
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2YDw.kt`
- `flutter/android/app/src/main/kotlin/com/cloudsend/app/nZW99cdXQ0COhB2o.kt`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`
- `flutter/android/app/build.gradle`
- `flutter/android/app/src/main/AndroidManifest.xml`
- `build.sh`

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

## 11. Final Baseline Before Implementation

Use this document plus the current source tree as the baseline for the next coding phase.

Implementation order should be:

1. Android ADB state skeleton.
2. Flutter ADB page status binding.
3. LADB runner port.
4. Manual pair/connect.
5. mDNS connect discovery.
6. Accessibility-assisted wireless-debugging setup.
7. Status monitor integration.
8. PC remote command protocol.

Every phase must preserve:

- Android screen share.
- PC connection.
- Side buttons.
- Monitor panel.
- Video stream.
- Screenshot stream.
- Existing build scripts.
