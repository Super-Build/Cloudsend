# ZEGO Voice Call Integration / ZEGO 语音通话接入

最后同步源码：2026-05-31

> 本文记录 CloudSend 1v1 第三方语音通话接入方案。它只复用现有语音按钮、来电确认、挂断控制入口；媒体能力改由 ZEGO RTC 承载，不再使用 RustDesk 原生 `audio_service` 语音通话推流链路。

---

## 1. Source Truth

代码入口：

- Protocol: `libs/hbb_common/protos/message.proto`
- PC/controller Rust: `src/client/helper.rs`, `src/client/io_loop.rs`
- Android/controlled Rust: `src/server/connection.rs`, `src/ipc.rs`, `src/ui_cm_interface.rs`
- Flutter event bridge: `src/flutter.rs`, `src/ui_session_interface.rs`
- Flutter ZEGO runtime: `flutter/lib/models/zego_voice_call_model.dart`
- Flutter event dispatch: `flutter/lib/models/model.dart`
- Flutter call state: `flutter/lib/models/chat_model.dart`, `flutter/lib/models/server_model.dart`
- PC toolbar: `flutter/lib/desktop/widgets/remote_toolbar.dart`
- Flutter dependency: `flutter/pubspec.yaml`
- Token service deployment: `docs/ZEGO_TOKEN_SERVICE_DEPLOYMENT.md`

官方接口依据：

- ZEGO Flutter package: `zego_express_engine: ^3.24.1`
- `loginRoom(roomID, ZegoUser, config: ZegoRoomConfig(..., token))`
- `startPublishingStream(streamID)`
- `startPlayingStream(streamID)`
- `onRoomStreamUpdate`

参考链接：

- https://pub.dev/packages/zego_express_engine
- https://pub.dev/documentation/zego_express_engine/latest/zego_express_engine/ZegoExpressEngineRoom/loginRoom.html
- https://pub.dev/documentation/zego_express_engine/latest/zego_express_engine/ZegoRoomConfig-class.html
- https://pub.dev/documentation/zego_express_engine/latest/zego_express_engine/ZegoExpressEnginePlayer/startPlayingStream.html
- https://pub.dev/documentation/zego_express_engine/latest/zego_express_engine/ZegoExpressEnginePublisher/startPublishingStream.html

---

## 2. Isolation Boundary

本功能的隔离边界：

- 不修改远控登录、握手、加密、KCP/TCP 通信主链路。
- 不修改视频采集、解码、首帧等待、`MediaProjection`、`ImageModel`、`on_rgba` 链路。
- 不修改侧按钮命令链、`wheeltouch` / `wheelblank` / `wheelbrowser` 等输入协议。
- 不修改 ADB/LADB、文件传输、剪贴板、terminal、端口转发。
- 不再从 `Data::NewVoiceCall` 成功后调用 `Remote::start_voice_call()`，因此 PC 不发送旧的 `AudioFrame` 语音通话数据。
- Android 接听后不再调用 `audio_service::set_voice_call_input_device(...)`，也不因语音通话订阅旧 `audio_service`。
- `src/client/io_loop.rs::Remote::start_voice_call` 已保留为 legacy guard，但函数体只记录并返回 `None`，防止未来误调用旧 RustDesk 音频推流。
- `src/server/connection.rs::handle_voice_call` 不再把 ZEGO 接听状态写入旧 `voice_calling=true`，避免音频权限/选项更新时误订阅旧 `audio_service`。

现有 CloudSend 连接仍只负责控制信令：

```text
PC voice button
  -> src/client/io_loop.rs Data::NewVoiceCall
  -> HTTPS token service
  -> VoiceCallRequest with ZEGO metadata
  -> Android incoming call UI
  -> VoiceCallResponse accepted/refused
  -> Flutter zego_voice_call_ready
  -> ZEGO SDK room login / publish / play
```

---

## 3. Protocol Shape

`VoiceCallRequest` 保留原字段：

- `req_timestamp`
- `is_connect`

新增 ZEGO metadata 字段：

- `rtc_provider`
- `app_id`
- `room_id`
- `caller_user_id`
- `callee_user_id`
- `caller_stream_id`
- `callee_stream_id`
- `caller_token`
- `callee_token`
- `expires_at`

`VoiceCallResponse` 不承载 Token，只保留接听/拒绝语义。PC 侧在发起请求时保存 `ZegoVoiceCallInfo`，Android 侧在收到请求时保存 callee payload。`callerToken` 只保留在 PC 内存中，`VoiceCallRequest.caller_token` 不发送真实值。

---

## 4. Token Service Contract

默认接口：

```text
POST https://api.unan.uno/api/v1/voice-call/create
Authorization: Bearer <VOICE_API_KEY>
Content-Type: application/json
```

请求体：

```json
{
  "pcPeerId": "pc id",
  "androidPeerId": "android id",
  "cloudsendSessionId": "request timestamp or session nonce"
}
```

响应体：

```json
{
  "rtcProvider": "zego",
  "appId": 123456789,
  "roomId": "cs_voice_xxx",
  "callerUserId": "pc_xxx",
  "calleeUserId": "android_xxx",
  "callerStreamId": "cs_voice_pub_xxx_pc",
  "calleeStreamId": "cs_voice_pub_xxx_android",
  "callerToken": "short lived token",
  "calleeToken": "short lived token",
  "expiresAt": 1780000000
}
```

客户端可通过本地配置覆盖默认值：

- `cloudsend-zego-token-url`
- `cloudsend-zego-token-api-key`

注意：`ZEGO_SERVER_SECRET` 只能存在于 token 服务端 `.env`，不能写入 PC / Android 客户端。

---

## 5. Runtime Behavior

PC/controller：

1. 点击现有语音按钮。
2. `request_zego_voice_call_info(...)` 向 token 服务取 `roomId` 和 caller/callee token。
3. 发送带 ZEGO metadata 的 `VoiceCallRequest`。
4. UI 进入 `VoiceCallStatus.waitingForResponse`。
5. Android 接听后，PC 收到 `VoiceCallResponse.accepted = true`。
6. Rust 推送 `zego_voice_call_ready`，Flutter 加入 ZEGO room。
7. Flutter 显示/打印 `ZEGO voice: loginRoom errorCode=0` 后，才代表 PC 端已经实际进入 ZEGO room。

Android/controlled：

1. 收到 `VoiceCallRequest.is_connect = true`。
2. 保存 ZEGO callee payload。
3. 仍通过现有 `VoiceCallIncoming` 弹出来电确认。
4. 用户接听后发送 `VoiceCallResponse.accepted = true`。
5. Rust 推送 `Data::ZegoVoiceCallReady` 到 connection manager。
6. Flutter 加入同一个 ZEGO room。
7. Flutter 显示/打印 `ZEGO voice: loginRoom errorCode=0` 后，才代表 Android 端已经实际进入 ZEGO room。

挂断：

- PC 侧 `sessionCloseVoiceCall` 继续发送 `VoiceCallRequest.is_connect = false`。
- 双端 Flutter 调用 `ZegoVoiceCallModel.leave()`，停止 play/publish 并 `logoutRoom`。

---

## 6. UI Rule

PC toolbar 中原 RustDesk 语音通话的麦克风设备选择菜单已隐藏：

- 删除 `_VoiceCallMenu` 中 `AudioInput(isVoiceCall: true)`。
- 保留 `End call` 控制。
- 旧 `set_voice_call_input_device` FFI 仍可供其他功能存在，但不再出现在本 ZEGO 语音通话入口中。

---

## 7. Verification Checklist

由于当前任务明确禁止执行编译命令，本次仅做静态核对。后续允许构建时建议验证：

- `flutter pub get`
- Windows PC package build
- Android APK build
- PC 控制 Android 首帧画面正常
- 侧按钮、ADB/LADB、文件传输、剪贴板、terminal 正常
- PC 点击语音按钮后 token 服务收到 `POST /api/v1/voice-call/create`
- Android 只收到对应 PC 的来电
- 两台 PC 同时呼叫不同 Android 时 `roomId` 不相同，互不串音
- 挂断后双端 ZEGO room 退出，下一次通话可重新加入
