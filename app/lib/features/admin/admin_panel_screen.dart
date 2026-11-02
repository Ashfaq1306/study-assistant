import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/providers.dart';
import '../../core/network/api_exception.dart';
import '../auth/application/auth_controller.dart';

/// The admin's home: the web Control Room (served by the API at /admin/) inside the app.
///
/// It deliberately looks nothing like the student and parent app. The panel gets its own
/// sign-in from `POST /v1/admin/panel-session`, so the panel and the app never share (and
/// rotate) one refresh token; the tokens are handed to the page's sessionStorage.
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  static const _background = Color(0xFF0B1120);
  static const _accent = Color(0xFF22D3EE);
  static const _storeKey = 'sa-admin-session';

  WebViewController? _controller;
  String? _error;
  var _progress = 0;
  var _handedOver = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _progress = 0;
      _handedOver = false;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/v1/admin/panel-session');
      final tokens = res['tokens']! as Map<String, Object?>;
      final session = jsonEncode({'accessToken': tokens['accessToken'], 'refreshToken': tokens['refreshToken']});
      final panelUrl = Uri.parse('${api.baseUrl}/admin/');

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(_background);
      await controller.addJavaScriptChannel(
        'StudyAssistantApp',
        onMessageReceived: (message) {
          // Signing out in the panel signs the admin out of the app too.
          if (message.message == 'signedOut') unawaited(ref.read(authControllerProvider.notifier).logout());
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          onPageFinished: (_) => _handOver(session),
          // Stay on the panel: anything else opens nowhere.
          onNavigationRequest: (request) {
            final uri = Uri.parse(request.url);
            return uri.host == panelUrl.host ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? false) && mounted) {
              setState(() => _error = 'The Control Room did not load. Check the connection and try again.');
            }
          },
        ),
      );
      // Set before loading, so the first onPageFinished can hand the session over.
      _controller = controller;
      if (mounted) setState(() {});
      await controller.loadRequest(panelUrl);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// First load only: puts the panel's own session in its storage and reloads, signed in.
  Future<void> _handOver(String session) async {
    if (_handedOver) return;
    _handedOver = true;
    await _controller?.runJavaScript(
      'sessionStorage.setItem(${jsonEncode(_storeKey)}, ${jsonEncode(session)}); location.reload();',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: _background, systemNavigationBarColor: _background),
      child: PopScope(
        // Back moves back inside the panel; it never leaves the Control Room by accident.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop && controller != null && await controller.canGoBack()) await controller.goBack();
        },
        child: Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: Column(
              children: [
                if (_progress < 100 && _error == null)
                  LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    color: _accent,
                    backgroundColor: _background,
                  ),
                Expanded(
                  child: _error != null
                      ? _ErrorView(message: _error!, onRetry: _open)
                      : controller == null
                      ? const Center(child: CircularProgressIndicator(color: _accent))
                      : WebViewWidget(controller: controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const ink = Color(0xFFE6EDF7);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFF22D3EE), size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE),
              foregroundColor: const Color(0xFF04131A),
            ),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Sign out', style: TextStyle(color: Color(0xFF8B9AB5))),
          ),
        ],
      ),
    );
  }
}
