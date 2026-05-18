# 文档真实性审计 / Document Audit

最后一次从关键源码锚点与文档一致性核验：2026-05-18

> 本文件用于回答两个问题：
>
> 1. 哪些文档可以直接信？
> 2. 哪些文档只能当背景材料，不能直接当实现真相？

审计等级：

- **A = 高可信**：大部分结论与当前源码一致
- **B = 部分可信**：方向对，但有局部漂移
- **C = 历史参考**：只能当背景，不能直接驱动改代码

---

## 0. 2026-05-18 CloudSend / 云计划 当前同步审计

当前工程文档主套件已同步 Part 1-4、Android 可见名称、版本号和 PC 新构建脚本的最终源码事实：

- Android package/applicationId: `com.cloudsend.app`；可见应用名与通知标题：`云计划`。
- Android Kotlin 主包路径：`flutter/android/app/src/main/kotlin/com/cloudsend/app/`。
- Android deep link scheme: `cloudsend://`。
- Rust crate / lib name: `cloudsend`；Android SO: `libcloudsend.so`。
- Kotlin 加载：`System.loadLibrary("cloudsend")`；Dart Android 加载：`DynamicLibrary.open('libcloudsend.so')`。
- FFI 导出符号：`cloudsend_core_main` / `cloudsend_core_main_args`。
- Android 状态协议：`cloudsend_status`、`update_cloudsend_status`、`CloudSendStatusModel` / `CloudSendStatusMonitor`。
- 配置键：`show_cloudsend_status_monitor` / `show-cloudsend-status-monitor`；虚拟显示 key：`cloudsend_virtual_displays`。

2026-05-18 additional source truth:

- Rust crate version: `5.2.1`.
- Flutter version: `5.2.1+59`.
- Windows DLL name and loading path: `cloudsend.dll`.
- Current Windows build script: `new-build.cmd`; output directory: `PC-Bulid`.
- Android app label source: `flutter/android/app/src/main/res/values/strings.xml` key `app_name = 云计划`.

审计结论：`ENGINEERING_INDEX.md`、`ENGINEERING_BASELINE.md`、`ENGINEERING_ANDROID_RUNTIME.md`、`TASK_ENTRYPOINTS.md`、`REPO_TRUE_STRUCTURE_MAP.md`、`CHANGELOG.md` 已作为当前可信项目记忆同步。旧名称只允许出现在迁移记录、历史说明、上游 README/贡献文档或明确 guardrail 中，不得作为当前实现依据。

---

## 0.1 2026-05-11 Android status monitor fallback audit

Current trusted docs have been synchronized with the Part 8 final source truth:

- `connection.rs` skips invalid/JNI-failed `cloudsend_status` samples and must not send hardcoded false-default JSON.
- `cloudsend_status_message()` returns `Option<Message>`.
- `DFm8Y8iMScvB2YDwGYN("cloudsend_status")` returns an empty string on exception.
- `CloudSendStatusModel.updateFromEvent()` preserves current/null values for missing keys.
- `MainService.onDestroy()` clears Rust `MAIN_SERVICE_CTX` through `ClsFx9V0S.VHsFQTvK()`.

Updated trusted docs: `CHANGELOG.md`, `ENGINEERING_BASELINE.md`, `ENGINEERING_ANDROID_RUNTIME.md`, and `TASK_ENTRYPOINTS.md`.

---

## 1. 工程文档主套件（Primary Engineering Docs）

### 1.1 `docs/ENGINEERING_INDEX.md` — 等级 A

状态：

- 可作为第一入口
- 当前作用是定义真相层级、阅读顺序、文档同步规则

注意：

- 本文件不应承担过多实现细节；实现真相应落到 baseline / runtime / task entrypoint

### 1.2 `docs/ENGINEERING_BASELINE.md` — 等级 A

状态：

- 当前已经覆盖了项目身份、顶层架构、关键链路、品牌/构建现实、已知风险
- 且关键结论都能回到源码锚点

注意：

- 若未来新增主链路（例如新的 Android 命令族、账号体系、平台产物），应优先补到这里

### 1.3 `docs/ENGINEERING_ANDROID_RUNTIME.md` — 等级 A

状态：

- 当前与 Android 源码的核心状态机相符
- 正确强调了：
  - service state
  - frame source state
  - waiting-for-first-frame state
  三者不能混用

注意：

- 任何涉及 `MediaProjection` / ignore fallback / waiting dialog / overlay keep-alive 的改动后，都必须同步回本文件

### 1.4 `docs/TASK_ENTRYPOINTS.md` — 等级 A

状态：

- 适合作为任务型导航
- 当前已经补齐：
  - `hbbs_http`
  - `privacy_mode`
  - `src/ui/`
  - build/package
  - Android 辅助面

注意：

- 这是入口地图，不是设计文档；不应塞过多实现细节

### 1.5 `docs/REPO_TRUE_STRUCTURE_MAP.md` — 等级 A

状态：

- 用于建立全仓结构心智模型
- 已覆盖主路径、兼容路径、平台路径、跨层主链

### 1.6 `docs/DOCUMENT_AUDIT.md` — 等级 A

状态：

- 用于限制错误信任范围
- 明确说明哪些文档可直接信、哪些只可参考

---

## 2. 现有仓库文档（Existing Repo Docs Outside Primary Suite）

### 2.1 `CLAUDE.md` — 等级 A-

优点：

- 是现有 Claude Code 入口
- 包含 Android 类名映射、构建命令、关键文件速查
- 当前已同步 CloudSend / 云计划 / 5.2.1 / new-build.cmd / libcloudsend.so / cloudsend.dll 的源码事实

已确认的边界：

1. **应服从工程文档主套件**
   - 它适合作为补充导航
   - 不应高于 `docs/ENGINEERING_*`

2. **实现细节不如工程文档主套件完整**
   - Android runtime、terminal、文档漂移审计等细节必须回到 `docs/ENGINEERING_*` 与源码核验

3. **Deep link 风险已经从 `CLAUDE.md` 漂移转为代码/配置并存风险**
   - `CLAUDE.md` 必须服从工程主文档；当前 Android scheme 是 `cloudsend://`。
   - 但当前源码仍同时存在：
     - Android manifest：`cloudsend`
     - Rust `get_uri_prefix()`：由 `APP_NAME = CloudSend` 推导，应与 `cloudsend://` 保持一致。

结论：

- `CLAUDE.md` 适合保留并使用
- 但只能当补充入口，不是最终真相层

### 2.2 `terminal.md` — 等级 C

优点：

- 仍保留 terminal 子系统的设计背景
- 对多 terminal / terminal tab / session 概念有参考价值

已确认漂移：

1. **service_id 叙述过时**
   - 文中以 `tmp_` / `persist_` 为核心
   - 当前 `src/server/terminal_service.rs::generate_service_id()` 使用的是 `ts_<uuid>`

2. **持久化恢复叙述不能直接当现行实现**
   - 文中提到了很多“想要实现 / 设计中的持久化恢复行为”
   - 当前代码不能直接等价为这些能力都已经落地

结论：

- `terminal.md` 只能作为历史背景或设计意图参考
- terminal 真相必须回到：
  - `src/server/terminal_service.rs`
  - `src/server/connection.rs`
  - `flutter/lib/models/terminal_model.dart`

### 2.3 `README*.md` / `CONTRIBUTING*.md` / `SECURITY*.md` — 等级 B/C

说明：

- 这些文档适合产品使用、贡献规范、社区说明
- 不适合作为项目运行时或工程主链的真相来源

---

## 3. 与源码冲突或易误导的点（Known Drift and Misleading Spots）

### 3.1 Android JNI 主模块

错误旧印象：

- `ffi.rs` 是主模块或 `pkg2230.rs` 的完整副本

当前源码事实：

- `libs/scrap/src/android/mod.rs` 只导出 `pkg2230`
- `ffi.rs` 仍保留相似逻辑，但不是当前主路由

### 3.2 项目是否“只有 Flutter UI”

错误旧印象：

- 新版项目已经完全摆脱旧桌面 UI

当前源码事实：

- `src/ui.rs` 与 `src/ui/` 仍存在
- 桌面侧不能只看 Flutter

### 3.3 是否只有远控，没有账号/同步/上传链路

错误旧印象：

- 工程主链只有远控会话与 Android 自定义命令

当前源码事实：

- `src/hbbs_http/` 是真实子系统
- 包括 OIDC、下载、上传、sync / pro 状态

### 3.4 品牌与命名是否已经完全统一

错误旧印象：

- 既然产品名是 CloudSend，则所有平台命名都已一致

当前源码事实：

- Android 当前加载 `libcloudsend.so`。
- Windows 当前加载 `cloudsend.dll`。
- `ORG` 仍是 `com.carriez`
- deep link scheme 与 Rust URI prefix 当前已统一到 `cloudsend` / `CloudSend`。
- Android visible label 是 `云计划`，但 runtime `APP_NAME` 仍是 `CloudSend`；不要把这两者混为同一个字段。

---

## 4. 当前最可信的项目记忆读取顺序（Recommended Memory Read Order）

对于 Codex / Claude Code：

1. `docs/ENGINEERING_INDEX.md`
2. `docs/ENGINEERING_BASELINE.md`
3. 若任务涉及 Android runtime，再读 `docs/ENGINEERING_ANDROID_RUNTIME.md`
4. `docs/TASK_ENTRYPOINTS.md`
5. `docs/REPO_TRUE_STRUCTURE_MAP.md`
6. 再去读源码
7. `CLAUDE.md` 仅作补充
8. `terminal.md` 仅作历史背景

---

## 5. 后续审计规则（How to Keep This Audit Current）

当以下任一情况发生时，必须重新审计本文件：

- 某份工程文档与源码出现冲突
- `CLAUDE.md` 更新后与工程文档出现分歧
- terminal / Android runtime / build 逻辑发生结构性变化
- 新增了新的“项目记忆型文档”

审计更新时必须写清：

- 哪份文档
- 等级变化
- 哪条事实过时
- 现在应该以哪份源码 / 工程文档为准
