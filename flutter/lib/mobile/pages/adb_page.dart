import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import 'home_page.dart';

class AdbPage extends StatefulWidget implements PageShape {
  @override
  final title = "ADB";

  @override
  final icon = const Icon(Icons.adb);

  @override
  final appBarActions = const <Widget>[];

  const AdbPage({Key? key}) : super(key: key);

  @override
  State<AdbPage> createState() => _AdbPageState();
}

class _AdbPageState extends State<AdbPage> {
  final _commandController = TextEditingController();
  final _terminalController = ScrollController();

  Timer? _pollTimer;
  String _terminalText = "";
  bool _busy = false;
  bool _shellReady = false;
  bool _serviceRequested = false;

  @override
  void initState() {
    super.initState();
    _appendLocalLine("CloudSend ADB module ready.");
    _appendLocalLine("Tap Start service to begin wireless-debugging setup.");
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commandController.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _startAdbFlow() async {
    setState(() {
      _busy = true;
      _serviceRequested = true;
      _shellReady = false;
    });
    _ensurePolling();
    _appendLocalLine("Requesting pairing information...");

    try {
      final state = await AndroidAdbManager.init();
      _applyState(state);
      if (state['paired'] == true) {
        _appendLocalLine("Paired before. Scanning and starting ADB automatically...");
        final started = await _startServerAfterPairing();
        if (started) return;
        _appendLocalLine("Automatic ADB start failed. Please pair again.");
      }
    } catch (e) {
      _appendLocalLine("ADB init failed: $e");
    }

    if (!mounted) return;
    final request = await _showPairDialog();
    if (!mounted) return;

    if (request == null) {
      _appendLocalLine("Pairing skipped.");
      await _startLocalShell();
      return;
    }

    setState(() => _busy = true);
    _appendLocalLine("Trying to pair localhost:${request.port} ...");
    try {
      final state = await AndroidAdbManager.pair(
        port: request.port,
        code: request.code,
      );
      _applyState(state);
      if (state['paired'] != true) {
        _appendLocalLine("Pairing did not complete. Please check the port and pairing code.");
        if (mounted) setState(() => _serviceRequested = false);
        return;
      }
      _appendLocalLine("Pairing succeeded. Starting ADB server...");
      await Future<void>.delayed(const Duration(seconds: 1));
      await _startServerAfterPairing();
    } catch (e) {
      _appendLocalLine("Pairing request failed: $e");
      if (mounted) setState(() => _serviceRequested = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLocalShell() async {
    try {
      final state = await AndroidAdbManager.startLocalShell();
      _applyState(state);
    } catch (e) {
      _appendLocalLine("Non-ADB shell start failed: $e");
      if (mounted) setState(() => _serviceRequested = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _startServerAfterPairing() async {
    _appendLocalLine("Starting ADB server...");
    var started = false;
    try {
      final state = await AndroidAdbManager.start();
      _applyState(state);
      started = state['shellReady'] == true;
    } catch (e) {
      _appendLocalLine("ADB start failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (!_shellReady) {
            _serviceRequested = false;
          }
        });
      }
    }
    return started;
  }

  Future<void> _sendCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;
    _commandController.clear();
    _appendLocalLine("> $command");
    try {
      final state = await AndroidAdbManager.command(command);
      _applyState(state);
    } catch (e) {
      _appendLocalLine("Command failed: $e");
    }
  }

  Future<_AdbPairRequest?> _showPairDialog() {
    final portController = TextEditingController();
    final codeController = TextEditingController();
    return showDialog<_AdbPairRequest>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("ADB \u914d\u5bf9"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "\u8bf7\u5728 Android \u65e0\u7ebf\u8c03\u8bd5\u7684\u201c\u4f7f\u7528\u914d\u5bf9\u7801\u914d\u5bf9\u8bbe\u5907\u201d\u9875\u9762\u4e2d\u8f93\u5165\u7aef\u53e3\u548c\u914d\u5bf9\u7801\u3002",
                style: Theme.of(context).textTheme.bodyMedium,
              ).marginOnly(bottom: 12),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "\u7aef\u53e3",
                  border: OutlineInputBorder(),
                ),
              ).marginOnly(bottom: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "\u914d\u5bf9\u7801",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text("\u8df3\u8fc7"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(_AdbPairRequest(
                port: portController.text,
                code: codeController.text,
              ));
            },
            child: const Text("\u914d\u5bf9"),
          ),
        ],
      ),
    ).whenComplete(() {
      portController.dispose();
      codeController.dispose();
    });
  }

  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      _refreshTerminalOutput();
    });
  }

  Future<void> _refreshTerminalOutput() async {
    try {
      final statusFuture = AndroidAdbManager.status();
      final outputFuture = AndroidAdbManager.output();
      final state = await statusFuture;
      final output = await outputFuture;
      if (!mounted) return;

      var changed = false;
      final nextShellReady = state['shellReady'] == true;
      if (_shellReady != nextShellReady) {
        _shellReady = nextShellReady;
        changed = true;
      }
      if (output.isNotEmpty && output != _terminalText) {
        _terminalText = output;
        changed = true;
      }
      if (!changed) return;
      setState(() {});
      _scrollTerminalToBottom();
    } catch (_) {
      // Keep the terminal stable if the native side is temporarily unavailable.
    }
  }

  void _applyState(Map<String, dynamic> state) {
    if (!mounted || state.isEmpty) return;
    final output = state['output']?.toString();
    setState(() {
      _shellReady = state['shellReady'] == true;
      if (output != null && output.isNotEmpty) {
        _terminalText = output;
      }
    });
    _scrollTerminalToBottom();
  }

  void _appendLocalLine(String line) {
    final now = DateTime.now();
    final stamp =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    setState(() {
      _terminalText = "$_terminalText[$stamp] $line\n";
    });
    _scrollTerminalToBottom();
  }

  void _scrollTerminalToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_terminalController.hasClients) return;
      _terminalController.jumpTo(_terminalController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _AdbCard(
                title: "ADB",
                titleIcon: const Icon(Icons.adb, color: MyTheme.accent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "\u540e\u7eed\u65e0\u7ebf\u8c03\u8bd5\u3001\u914d\u5bf9\u72b6\u6001\u548c\u8fdc\u7a0b\u547d\u4ee4\u7ec4\u4ef6\u90fd\u4f1a\u653e\u5728\u8fd9\u91cc\u3002",
                      style: TextStyle(color: MyTheme.darkGray),
                    ).marginOnly(bottom: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: _busy ? null : _startAdbFlow,
                        label: Text(_busy
                            ? "\u7b49\u5f85\u914d\u5bf9"
                            : "\u542f\u52a8\u670d\u52a1"),
                      ),
                    ),
                  ],
                ),
              ),
              _AdbCard(
                title: "\u81ea\u52a8\u5316\u65e0\u7ebf\u8c03\u8bd5",
                titleIcon:
                    const Icon(Icons.settings_remote, color: MyTheme.accent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "\u540e\u7eed\u7528\u4e8e\u57fa\u4e8e\u65e0\u969c\u788d\u534a\u81ea\u52a8\u6253\u5f00 Android \u65e0\u7ebf\u8c03\u8bd5\u5f00\u5173\u3002",
                      style: TextStyle(color: MyTheme.darkGray),
                    ).marginOnly(bottom: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.settings_remote),
                        onPressed: () {},
                        label: const Text("\u6253\u5f00\u8c03\u8bd5"),
                      ),
                    ),
                  ],
                ),
              ),
              _AdbTerminalCard(
                busy: _busy || (_serviceRequested && !_shellReady),
                controller: _terminalController,
                text: _terminalText,
              ),
              _AdbCommandCard(
                controller: _commandController,
                enabled: _shellReady,
                onSubmitted: _sendCommand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdbPairRequest {
  const _AdbPairRequest({
    required this.port,
    required this.code,
  });

  final String port;
  final String code;
}

class _AdbTerminalCard extends StatelessWidget {
  const _AdbTerminalCard({
    Key? key,
    required this.busy,
    required this.controller,
    required this.text,
  }) : super(key: key);

  final bool busy;
  final ScrollController controller;
  final String text;

  @override
  Widget build(BuildContext context) {
    final terminalHeight =
        (MediaQuery.of(context).size.height * 0.28).clamp(150.0, 240.0);
    final theme = Theme.of(context);
    return SizedBox(
      width: double.maxFinite,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Container(
            height: terminalHeight,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              children: [
                if (busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _AdbTerminalOutput(
                    controller: controller,
                    text: text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdbTerminalOutput extends StatelessWidget {
  const _AdbTerminalOutput({
    Key? key,
    required this.controller,
    required this.text,
  }) : super(key: key);

  final ScrollController controller;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            text,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdbCommandCard extends StatelessWidget {
  const _AdbCommandCard({
    Key? key,
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  }) : super(key: key);

  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: controller,
            enabled: enabled,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              onSubmitted();
            },
            decoration: InputDecoration(
              hintText: enabled
                  ? "ADB \u547d\u4ee4"
                  : "\u7b49\u5f85 ADB Shell \u5c31\u7eea",
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: enabled
                    ? () {
                        onSubmitted();
                      }
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdbCard extends StatelessWidget {
  const _AdbCard({
    Key? key,
    required this.title,
    required this.child,
    this.titleIcon,
  }) : super(key: key);

  final String title;
  final Widget child;
  final Widget? titleIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
                child: Row(
                  children: [
                    if (titleIcon != null) titleIcon!.marginOnly(right: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.merge(
                              const TextStyle(fontWeight: FontWeight.bold),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
