import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SingBox.instance.initialize(
    const SingBoxOptions(
      android: SingBoxAndroidOptions(
        notificationTitle: 'ClaudeVPN',
        showTrafficInNotification: true,
        stopActionTitle: 'Отключить',
      ),
    ),
  );
  runApp(const ClaudeVpnApp());
}

class ClaudeVpnApp extends StatelessWidget {
  const ClaudeVpnApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ClaudeVpnHome(),
      );
}

class ClaudeVpnHome extends StatefulWidget {
  const ClaudeVpnHome({super.key});

  @override
  State<ClaudeVpnHome> createState() => _ClaudeVpnHomeState();
}

class _ClaudeVpnHomeState extends State<ClaudeVpnHome> {
  WebViewController? _web;
  StreamSubscription? _statsSub;
  StreamSubscription? _stateSub;
  bool _pageReady = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = WebViewController();
    _web = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF050505));
    await controller.enableZoom(false);
    await controller.addJavaScriptChannel(
      'VpnBridge',
      onMessageReceived: (message) => _onBridge(message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          _pageReady = true;
          _sendState(SingBox.instance.status.isActive ? 'connected' : 'disconnected');
        },
      ),
    );
    await controller.loadFlutterAsset('assets/index.html');

    _statsSub = SingBox.instance.watchConnectionStats().listen((s) {
      _sendStats({
        'download': _formatBytes(s.downloadTotal),
        'upload': _formatBytes(s.uploadTotal),
        'time': _formatDuration(s.duration),
      });
    });

    _stateSub = SingBox.instance.watchConnectionState().listen((s) {
      if (s.error != null) {
        _sendState('error', s.error.toString());
      }
    });

    if (mounted) setState(() {});
  }

  String _formatBytes(num value) {
    if (value < 1024) return '${value.toInt()} B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  Future<void> _onBridge(String raw) async {
    if (_busy) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['action']) {
      case 'connect':
        await _connect();
        break;
      case 'disconnect':
        await _disconnect();
        break;
    }
  }

  /// Серверы лежат в assets/servers.json: массив sing-box outbound'ов,
  /// сконвертированный из исходного Xray-конфига. sing_box сам собирает из
  /// массива селектор `proxy` с автоматическим urltest (`auto`).
  Future<void> _connect() async {
    _busy = true;
    _sendState('connecting');
    try {
      final servers = await rootBundle.loadString('assets/servers.json');
      await SingBox.instance.connect(servers);
      _sendState('connected');
    } on SingBoxException catch (e) {
      _sendState('error', e.message);
    } catch (e) {
      _sendState('error', e.toString());
    } finally {
      _busy = false;
    }
  }

  Future<void> _disconnect() async {
    _busy = true;
    try {
      await SingBox.instance.disconnect();
      _sendState('disconnected');
    } catch (e) {
      _sendState('error', e.toString());
    } finally {
      _busy = false;
    }
  }

  void _sendState(String state, [String? message]) {
    if (!_pageReady) return;
    final payload = jsonEncode({'state': state, if (message != null) 'message': message});
    _web?.runJavaScript(
      "window.dispatchEvent(new CustomEvent('vpnstate',{detail:$payload}));",
    );
  }

  void _sendStats(Map<String, String> stats) {
    if (!_pageReady) return;
    final payload = jsonEncode(stats);
    _web?.runJavaScript(
      "window.dispatchEvent(new CustomEvent('vpnstats',{detail:$payload}));",
    );
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_web == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF050505),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6A1F))),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(child: WebViewWidget(controller: _web!)),
    );
  }
}