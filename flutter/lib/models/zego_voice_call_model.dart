import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

class ZegoVoiceCallPayload {
  final String rtcProvider;
  final int appId;
  final String roomId;
  final String userId;
  final String userName;
  final String token;
  final String publishStreamId;
  final String playStreamId;
  final String role;
  final int expiresAt;

  ZegoVoiceCallPayload({
    required this.rtcProvider,
    required this.appId,
    required this.roomId,
    required this.userId,
    required this.userName,
    required this.token,
    required this.publishStreamId,
    required this.playStreamId,
    required this.role,
    required this.expiresAt,
  });

  factory ZegoVoiceCallPayload.fromJson(Map<String, dynamic> json) {
    return ZegoVoiceCallPayload(
      rtcProvider: json['rtcProvider']?.toString() ?? '',
      appId: int.tryParse(json['appId']?.toString() ?? '') ?? 0,
      roomId: json['roomId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      publishStreamId: json['publishStreamId']?.toString() ?? '',
      playStreamId: json['playStreamId']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      expiresAt: int.tryParse(json['expiresAt']?.toString() ?? '') ?? 0,
    );
  }

  bool get isValid =>
      rtcProvider == 'zego' &&
      appId > 0 &&
      roomId.isNotEmpty &&
      userId.isNotEmpty &&
      token.isNotEmpty &&
      publishStreamId.isNotEmpty &&
      playStreamId.isNotEmpty;
}

class ZegoVoiceCallModel extends ChangeNotifier {
  static bool _engineCreated = false;
  static int? _engineAppId;

  ZegoVoiceCallPayload? _payload;
  bool _joined = false;
  bool _playing = false;
  bool _muted = false;

  bool get joined => _joined;
  bool get muted => _muted;

  Future<void> joinFromJson(String payloadJson) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('payload is not a JSON object');
      }
      final payload = ZegoVoiceCallPayload.fromJson(decoded);
      if (!payload.isValid) {
        throw FormatException('invalid ZEGO voice-call payload');
      }
      _trace(
        'payload received role=${payload.role} room=${payload.roomId}',
        toast: true,
      );
      await join(payload);
    } catch (e) {
      _trace('join failed: $e', toast: true);
      await leave();
    }
  }

  Future<void> join(ZegoVoiceCallPayload payload) async {
    if (_joined) {
      await leave();
    }

    _payload = payload;
    _trace('creating engine appId=${payload.appId}');
    await _ensureEngine(payload.appId);
    _trace('engine ready');
    _installCallbacks();

    final engine = ZegoExpressEngine.instance;
    await engine.enableCamera(false);
    await engine.mutePublishStreamVideo(true);
    await engine.muteMicrophone(false);
    await engine.muteSpeaker(false);

    final config = ZegoRoomConfig(0, true, payload.token);
    final result = await engine.loginRoom(
      payload.roomId,
      ZegoUser(payload.userId, payload.userName),
      config: config,
    );
    _trace('loginRoom errorCode=${result.errorCode}', toast: true);
    if (result.errorCode != 0) {
      throw StateError('ZEGO loginRoom failed: ${result.errorCode}');
    }

    _joined = true;
    await engine.startPublishingStream(payload.publishStreamId);
    _trace('publishing stream=${payload.publishStreamId}', toast: true);
    await _startPlayingIfNeeded(payload.playStreamId);
    notifyListeners();
  }

  Future<void> leave() async {
    final payload = _payload;
    if (payload == null && !_joined) return;

    try {
      final engine = ZegoExpressEngine.instance;
      if (_playing && payload != null) {
        await engine.stopPlayingStream(payload.playStreamId);
      }
      if (payload != null) {
        await engine.stopPublishingStream();
        await engine.logoutRoom(payload.roomId);
      }
    } catch (e) {
      debugPrint('leave ZEGO voice call failed: $e');
    } finally {
      _payload = null;
      _joined = false;
      _playing = false;
      _muted = false;
      _trace('left room');
      notifyListeners();
    }
  }

  Future<void> setMuted(bool muted) async {
    if (!_joined) return;
    _muted = muted;
    await ZegoExpressEngine.instance.muteMicrophone(muted);
    notifyListeners();
  }

  Future<void> toggleMuted() => setMuted(!_muted);

  Future<void> _ensureEngine(int appId) async {
    if (_engineCreated && _engineAppId == appId) return;
    if (_engineCreated) {
      await ZegoExpressEngine.destroyEngine();
      _engineCreated = false;
      _engineAppId = null;
      _trace('destroyed previous engine');
    }

    final profile = ZegoEngineProfile(
      appId,
      ZegoScenario.StandardVoiceCall,
      appSign: '',
    );
    await ZegoExpressEngine.createEngineWithProfile(profile);
    _engineCreated = true;
    _engineAppId = appId;
    _trace('created engine');
  }

  void _installCallbacks() {
    ZegoExpressEngine.onRoomStreamUpdate =
        (roomId, updateType, streamList, extendedData) {
      final payload = _payload;
      if (payload == null || roomId != payload.roomId) return;
      final hasPeerStream =
          streamList.any((stream) => stream.streamID == payload.playStreamId);
      if (!hasPeerStream) return;

      if (updateType == ZegoUpdateType.Add) {
        unawaited(_startPlayingIfNeeded(payload.playStreamId));
      } else if (updateType == ZegoUpdateType.Delete) {
        _playing = false;
      }
    };
  }

  Future<void> _startPlayingIfNeeded(String streamId) async {
    if (_playing || streamId.isEmpty) return;
    try {
      await ZegoExpressEngine.instance.startPlayingStream(streamId);
      _playing = true;
      _trace('playing stream=$streamId', toast: true);
    } catch (e) {
      _trace('start play failed: $e', toast: true);
    }
  }

  void _trace(String message, {bool toast = false}) {
    final text = 'ZEGO voice: $message';
    debugPrint(text);
    if (toast) {
      BotToast.showText(text: text);
    }
  }
}
