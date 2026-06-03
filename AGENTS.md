# AGENTS.md — CloudSend / 云计划 v5.2.1

最后一次与全仓源码对齐：2026-06-03
最近一次文档分层整理：2026-06-03

> 本文件是 **Codex** 的项目入口说明。
> 它是补充导航，不是最终真相层。
> 每次会话开始时请优先阅读：
>
> 1. `docs/ENGINEERING_INDEX.md`
> 2. `docs/ENGINEERING_BASELINE.md`
> 3. 若任务涉及 Android 运行时，再读 `docs/ENGINEERING_ANDROID_RUNTIME.md`
> 4. `docs/TASK_ENTRYPOINTS.md`
>
> 本文件中的中文用于解释；**代码路径、类名、函数名、常量、构建产物名一律保留英文原文**，以避免检索歧义。

---

## 1. 项目身份（Project Identity）

- 产品/runtime 名：`CloudSend`
- Android 显示名：`云计划`
- 基础：RustDesk 深度二次开发
- Rust crate：`cloudsend`
- Rust library：`cloudsend`
- Flutter package：`flutter_hbb`
- Android package/applicationId：`com.cloudsend.app`
- Android deep link scheme：`cloudsend`
- Runtime `APP_NAME`：`CloudSend`（`libs/hbb_common/src/config.rs` / `hbb_common::config::APP_NAME`）
- Runtime `ORG`：`com.carriez`（仍有历史来源，非 Android package）
- 当前版本：Rust `5.2.1`，Flutter `5.2.1+59`

---

## 2. 先建立的心智模型（Mental Model First）

这个项目不是单一路径应用，而是多层并存：

1. Rust core：`src/`
2. Shared protocol/config：`libs/hbb_common/`
3. Android JNI / raw frame：`libs/scrap/src/android/`
4. Flutter UI：`flutter/lib/`
5. Android Kotlin runtime：`flutter/android/app/src/main/kotlin/com/cloudsend/app/`
6. Legacy desktop UI：`src/ui/`
7. Account / HTTP / sync / upload：`src/hbbs_http/`
8. Windows privacy mode / virtual display：`src/privacy_mode.rs` + `src/virtual_display_manager.rs`
9. Android local ADB/LADB：`flutter/android/app/src/main/kotlin/com/cloudsend/app/adb/` + `flutter/lib/mobile/pages/adb_page.dart`
10. ZEGO voice call：Flutter RTC side path + Rust control-channel invitation state

不要把项目误读成：

- 只有 Flutter，没有旧 UI
- 只有远控，没有账号/同步链
- Android 只有 Kotlin，没有 Rust JNI 主链
- ADB/LADB 只是外部研究目录；当前 Android 本地 ADB 已有落地模块
- ZEGO 语音走 RustDesk 原 `audio_service`；当前媒体只走 ZEGO SDK
- 品牌/运行名已经迁移到 CloudSend，但上游文档、翻译、兼容判断和第三方依赖中仍会有历史 RustDesk 字样

---

## 3. Android 类名映射（Android Class Map）

- `oFtTiPzsqzBHGigp.kt` = `FlutterActivity`
- `XerQvgpGBzr8FDFr.kt` = 权限 / 透明 Activity
- `DFm8Y8iMScvB2YDw.kt` = `MainService`（`MediaProjection`, keep-alive）
- `nZW99cdXQ0COhB2o.kt` = `AccessibilityService`（输入 / fallback / overlay）
- `DFrLMwitwQbfu7AC.kt` = `FloatWindowService`
- `BootReceiver.kt` = 开机启动
- `ig2xH1U3RDNsb7CS.kt` = 剪贴板桥
- `EqljohYazB0qrhnj.kt` = 图像辅助
- `common.kt` = Android 全局状态
- `KeyboardKeyEventMapper.kt` = 键盘映射
- `VolumeController.kt` = 音量控制
- `adb/CloudSendAdbManager.kt` = Android local ADB/LADB facade
- `adb/CloudSendAdbRunner.kt` = packaged `libadb.so` runner
- `adb/CloudSendAdbDnsDiscover.kt` = wireless debugging mDNS discovery
- `adb/CloudSendAdbState.kt` = ADB state snapshot
- `pkg2230.kt` = 主 JNI bridge
- `ffi.kt` = 兼容 JNI bridge
- `p50.java` + `q50.java` = XOR / 混淆辅助

---

## 4. 关键工程真相（High-Value Facts）

### 4.1 Android JNI 主路由

- 当前生效模块：`libs/scrap/src/android/pkg2230.rs`
- 兼容模块：`libs/scrap/src/android/ffi.rs`
- `libs/scrap/src/android/mod.rs` 当前只导出 `pkg2230`

结论：

- 修改 Android JNI 时，以 `pkg2230.rs` 为主
- `ffi.rs` 不能假设与其完全相同，但改动后应有意识检查

### 4.2 Android 三条采集/显示路径

- 正常共享路径（`normal MediaProjection video path`）
- 穿透路径（`SKL pass-through path`）
- 无视回退路径（`ignore-capture fallback path`）

关键状态：

- Kotlin：`SKL`, `shouldRun`, `gohome`, `BIS`, `SCREEN_INFO`
- Rust JNI：`VIDEO_RAW`, `PIXEL_SIZEBack`, `PIXEL_SIZEBack8`, `force_next`

### 4.3 waiting-for-image 不是等于 Android 服务状态

PC 侧关键状态在：

- `flutter/lib/models/model.dart`
  - `waitForFirstImage`
  - `waitForImageTimer`
  - `showConnectedWaitingForImage()`
  - `onEvent2UIRgba()`

要点：

- 服务活着 != 已经有首帧
- Android core connection/id service != Android screen sharing；`Start service` / `Stop service` 只控制 `MediaProjection` 屏幕共享。
- PC waiting-for-image 不得自动发送"开无视"、截屏 fallback 或 `sessionRefreshVideo(...)`；只能等待真实帧或用户手动点击"开无视"。
- 侧按钮 `开共享`/`关共享` 是 Android runtime 的主动操作：`开共享` 可临时无视兜底并在共享恢复后一次性清无视，`关共享` 可在无障碍存在时自动切无视保画面。
- Android 掉线自动重连是 5s 单 timer、无限重试、不可堆叠。
- 任何真实 RGBA 帧到达 UI 时都应清理 waiting

### 4.4 登录逻辑要分两层看

- Rust：`src/common.rs::verify_login()`（当前近似绕过）
- 产品账号：`flutter/lib/models/user_model.dart`
  - `ChinaNetworkTimeService`
  - `validateUser()`
  - `mainGetUuid()`

### 4.5 账号 / 下载 / 上传不是边角料

以下是真实子系统：

- `src/hbbs_http/account.rs`
- `src/hbbs_http/downloader.rs`
- `src/hbbs_http/record_upload.rs`
- `src/hbbs_http/sync.rs`

### 4.6 Windows 平台还包含独立维护面

- `src/privacy_mode.rs`
- `src/privacy_mode/win_virtual_display.rs`
- `src/virtual_display_manager.rs`

---

## 5. 命令协议速查（Android Command Quick Map）

Flutter / Rust 命令字符串：

- `wheelblank`
- `wheelbrowser`
- `wheelanalysis`
- `wheelback`
- `wheelstart`
- `wheelstop`

Rust 映射：

- `MOUSE_TYPE_BLANK = 5`
- `MOUSE_TYPE_BROWSER = 6`
- `MOUSE_TYPE_Analysis = 7`
- `MOUSE_TYPE_GoBack = 8`
- `MOUSE_TYPE_START = 9`
- `MOUSE_TYPE_STOP = 10`

主链路：

`overlay.dart`  
→ `input_model.dart`  
→ `src/flutter_ffi.rs`  
→ `src/ui_session_interface.rs`  
→ `src/client.rs`  
→ `message.proto`  
→ `src/server/connection.rs`  
→ `pkg2230.rs`  
→ Kotlin services

---

## 6. 构建命令（Build Commands）

### Android（Linux 构建机）

```bash
./build.sh 1
./build.sh 2
```

### Windows / PC（Windows Server 构建机）

```bat
new-build.cmd
```

说明：

- `new-build.cmd` 适配 `PC-Build.md` 中的 `C:\DevEnv` + `C:\DevTool` 环境。
- 生成的自解压产物输出到：`PC-Bulid\<源码目录名>.exe`。
- 旧 `build.cmd` 仍保留，但不是当前推荐的新环境入口。

### Desktop / Flutter（通用）

```bash
python3 build.py --flutter --release
cd flutter && flutter pub get
cd flutter && flutter build apk --release
```

### Rust

```bash
cargo build --release --features flutter
cargo test
```

---

## 7. 构建产物与命名现实（Artifact Naming Reality）

### Android

- Rust 输出：`libcloudsend.so`
- `build.sh` 复制到：`flutter/android/app/src/main/jniLibs/<abi>/libcloudsend.so`
- Kotlin 加载：`System.loadLibrary("cloudsend")`
- Dart Android 打开：`DynamicLibrary.open('libcloudsend.so')`
- Android 可见应用名：`云计划`

### Windows

- Runner 加载：`cloudsend.dll`
- Dart Windows 打开：`DynamicLibrary.open('cloudsend.dll')`
- `flutter/windows/CMakeLists.txt` 从 `target/<profile>/cloudsend.dll` 安装为 `cloudsend.dll`

### Deep Link

请不要再把 deep link 简化成唯一真相。

当前要区分：

- Android manifest scheme：`cloudsend`
- Rust `get_uri_prefix()`：由 `APP_NAME = CloudSend` 推导，必须与 `cloudsend://` 保持一致

因此，任何 deep-link 任务都必须同时核对 manifest 与 Rust helper。

---

## 8. 常用入口文件（Common Entrypoints）

| 主题 | 文件 |
|---|---|
| 启动分流 | `src/main.rs`, `src/core_main.rs`, `flutter/lib/main.dart` |
| 自定义 Android 命令 | `overlay.dart`, `input_model.dart`, `src/flutter_ffi.rs`, `src/server/connection.rs`, `pkg2230.rs`, Kotlin services |
| Android runtime | `DFm8Y8iMScvB2YDw.kt`, `nZW99cdXQ0COhB2o.kt`, `common.kt`, `pkg2230.rs` |
| waiting/reconnect | `flutter/lib/models/model.dart`, `flutter/lib/common.dart`, `src/server/connection.rs` |
| 登录/账号 | `flutter/lib/models/user_model.dart`, `src/common.rs`, `src/hbbs_http/account.rs` |
| 终端 | `src/server/terminal_service.rs`, `src/server/connection.rs`, `flutter/lib/models/terminal_model.dart` |
| ZEGO 语音 | `docs/ZEGO_VOICE_CALL_ARCHITECTURE.md`, `docs/ZEGO_VOICE_CALL_INTEGRATION.md`, `docs/ZEGO_TOKEN_SERVICE_DEPLOYMENT.md`, `flutter/lib/models/zego_voice_call_model.dart` |
| 插件 | `src/plugin/`, `flutter/lib/plugin/` |
| 隐私模式/虚拟显示 | `src/privacy_mode.rs`, `src/privacy_mode/win_*`, `src/virtual_display_manager.rs` |
| 构建/命名 | `build.sh`, `Cargo.toml`, `config.rs`, `native_model.dart`, `main.cpp` |
| 文档整理 | `docs/ENGINEERING_INDEX.md`, `docs/DOCUMENT_AUDIT.md`, `docs/TASK_ENTRYPOINTS.md`, `docs/REPO_TRUE_STRUCTURE_MAP.md` |

---

## 9. 修改注意事项（Mutation Rules）

1. **先读工程文档主套件，再改代码**
2. **保持中文解释 + English anchor 写法**
3. **改 Android JNI 后主动检查 `ffi.rs`**
4. **改命令链必须检查完整跨层链路**
5. **改品牌 / 命名 / deep link / SO / DLL 时做全链路核对**
6. **改 terminal 时不要再直接相信 `terminal.md`**
7. **改 Android runtime 时不要把 service state 与 frame state 混为一谈**
8. **代码事实发生变化后，同步更新 `docs/ENGINEERING_*` 文档**

---

## 10. 本文件与其他文档的关系

- 真相层：`docs/ENGINEERING_*`
- 任务导航：`docs/TASK_ENTRYPOINTS.md`
- 结构地图：`docs/REPO_TRUE_STRUCTURE_MAP.md`
- 文档可信度审计：`docs/DOCUMENT_AUDIT.md`
- 本文件：Codex 的补充入口与速查表

若本文件与工程文档冲突，以工程文档和源码为准。
