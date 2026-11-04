import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  SharedPreferences? _prefs;
  bool _pageReady = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final controller = WebViewController();
    _web = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
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
      case 'subscription':
        await _editSubscription();
        break;
      case 'connect':
        await _connect();
        break;
      case 'disconnect':
        await _disconnect();
        break;
    }
  }

  Future<void> _editSubscription() async {
    final controller = TextEditingController(
      text: _prefs?.getString('subscription_url') ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ссылка подписки'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://…',
            helperText: 'Ссылка хранится только на этом устройстве.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await _prefs?.setString('subscription_url', value);
    _sendState('disconnected', 'Подписка сохранена');
  }

  Future<String> _downloadSubscription(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('Укажите полную ссылку подписки, начинающуюся с https://');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = true
      ..userAgent = 'ClaudeVPN/1.0';

    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 25));
      request.headers.set(HttpHeaders.acceptHeader,
          'text/plain, application/json, application/octet-stream, */*');
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 35));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('Сервер подписки ответил HTTP ${response.statusCode}');
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (all, chunk) {
          if (all.length + chunk.length > 5 * 1024 * 1024) {
            throw const FormatException('Файл подписки слишком большой (больше 5 МБ)');
          }
          return all..addAll(chunk);
        },
      ).timeout(const Duration(seconds: 35));

      final body = utf8.decode(bytes, allowMalformed: true).trim();
      if (body.isEmpty) {
        throw const FormatException('Ссылка открылась, но подписка пустая');
      }
      final lower = body.toLowerCase();
      if (lower.startsWith('<!doctype html') || lower.startsWith('<html') ||
          lower.contains('<title>') && lower.contains('</html>')) {
        throw const FormatException(
          'Ссылка вернула HTML-страницу, а не список серверов. Проверьте ссылку подписки.',
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _connect() async {
    final url = _prefs?.getString('subscription_url')?.trim() ?? '';
    if (url.isEmpty) {
      await _editSubscription();
      return;
    }
    _busy = true;
    _sendState('connecting', 'Загрузка подписки…');
    try {
      final subscription = await _downloadSubscription(url);
      _sendState('connecting', 'Проверка серверов…');
      // sing-box parses plain links, multiline subscriptions, Base64 and JSON.
      // Multiple servers are placed into an automatic URL-test selector.
      await SingBox.instance.connect(subscription);
      _sendState('connected');
    } on SingBoxException catch (e) {
      _sendState('error', e.message);
    } on TimeoutException {
      _sendState('error', 'Не удалось загрузить подписку вовремя. Проверьте интернет и повторите попытку.');
    } catch (e) {
      _sendState('error', e.toString().replaceFirst('Exception: ', ''));
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