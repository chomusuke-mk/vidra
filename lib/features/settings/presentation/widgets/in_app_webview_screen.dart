import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:math' as math;

import '../../data/cookie_exporter.dart';

/// Full-screen in-app WebView screen / dialog that enables users to browse,
/// log in to authenticated websites, and capture/export session and persistent
/// cookies to a standard Netscape cookie file.

const _defaultSearchEngineURL = 'https://search.brave.com/search?q=';
const _defaultSearchEngineName = 'Brave';
const _defaultSearchEngineIcon = FaIcon(
  FontAwesomeIcons.brave,
  color: Colors.deepOrange,
);

class InAppWebViewScreen extends StatefulWidget {
  final String initialUrl;
  final Widget? webView;

  const InAppWebViewScreen({
    super.key,
    this.initialUrl = _defaultSearchEngineURL,
    this.webView,
  });

  /// Displays the [InAppWebViewScreen] as a full-screen dialog route and
  /// returns the absolute path of the generated cookie file, or `null` if dismissed.
  static Future<String?> show(
    BuildContext context, {
    String initialUrl = _defaultSearchEngineURL,
    Widget? webView,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            InAppWebViewScreen(initialUrl: initialUrl, webView: webView),
        fullscreenDialog: true,
      ),
    );
  }

  /// Normalizes a given URL string, prepending `https://` if the protocol scheme is missing.
  static String normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return _defaultSearchEngineURL;
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
      return trimmed;
    }
    return _defaultSearchEngineURL + Uri.encodeComponent(trimmed);
  }

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  late final TextEditingController _urlController;
  final TextEditingController _shortcutController = TextEditingController();
  final FocusNode _focusNodeURL = FocusNode();
  bool _alreadyFocusedURL = false;
  late AnimationController _shakeController;
  Timer? _shakeTimer;

  bool _isLoading = false;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: InAppWebViewScreen.normalizeUrl(widget.initialUrl),
    );
    _focusNodeURL.addListener(() {
      if (!_focusNodeURL.hasFocus) {
        _alreadyFocusedURL = false;
      }
    });
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _shakeTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_isCapturing) {
        _shakeController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _focusNodeURL.dispose();
    _urlController.dispose();
    _shortcutController.dispose();
    _shakeTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _loadUrl(String rawUrl) {
    final normalized = InAppWebViewScreen.normalizeUrl(rawUrl);
    _urlController.text = normalized;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(normalized)),
    );
  }

  Future<void> _captureCookies() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final WebUri? currentWebUri = await _webViewController?.getUrl();
      final String fallbackUrl = InAppWebViewScreen.normalizeUrl(
        _urlController.text,
      );
      final Uri effectiveUri =
          currentWebUri?.uriValue ?? Uri.parse(fallbackUrl);

      final cookieManager = CookieManager.instance();
      final List<Cookie> cookies = await cookieManager.getCookies(
        url: WebUri(effectiveUri.toString()),
      );

      if (!mounted) return;

      if (cookies.isEmpty) {
        final host = effectiveUri.host.isNotEmpty
            ? effectiveUri.host
            : effectiveUri.toString();
        debugPrint('No cookies found for $host');
        ToastUtils.showError('No cookies found for $host');
        return;
      }

      final defaultDomain = effectiveUri.host.isNotEmpty
          ? effectiveUri.host
          : 'localhost';
      debugPrint(
        'Capturing ${cookies.length} cookies for domain: $defaultDomain',
      );
      final String savedFilePath = await CookieExporter.saveCookiesToFile(
        cookies,
        defaultDomain: defaultDomain,
      );

      if (!mounted) return;

      Navigator.of(context).pop(savedFilePath);
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError('Error capturing cookies: $e');
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Widget _buildWebViewBody(BuildContext context) {
    if (widget.webView != null) {
      return widget.webView!;
    }

    if (InAppWebViewPlatform.instance == null) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(InAppWebViewScreen.normalizeUrl(widget.initialUrl)),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportMultipleWindows: false,
        isInspectable: kDebugMode,
        transparentBackground: false,
        thirdPartyCookiesEnabled: true,
        allowBackgroundAudioPlaying: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useHybridComposition: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) {
          return NavigationActionPolicy.ALLOW;
        }

        final scheme = uri.scheme.toLowerCase();
        // Allow standard web schemes
        if (scheme == 'http' ||
            scheme == 'https' ||
            scheme == 'about' ||
            scheme == 'data' ||
            scheme == 'javascript') {
          return NavigationActionPolicy.ALLOW;
        }
        // Cancel navigation inside the WebView to prevent ERR_UNKNOWN_URL_SCHEME
        return NavigationActionPolicy.CANCEL;
      },
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
      onLoadStart: (controller, url) {
        if (mounted) {
          setState(() {
            _isLoading = true;
            if (url != null) {
              _urlController.text = url.toString();
            }
          });
        }
      },
      onProgressChanged: (controller, progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _isLoading = progress < 100;
          });
        }
      },
      onLoadStop: (controller, url) async {
        final canBack = await controller.canGoBack();
        final canFwd = await controller.canGoForward();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _canGoBack = canBack;
            _canGoForward = canFwd;
            if (url != null) {
              _urlController.text = url.toString();
            }
          });
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        final canBack = await controller.canGoBack();
        final canFwd = await controller.canGoForward();
        if (mounted) {
          setState(() {
            _canGoBack = canBack;
            _canGoForward = canFwd;
            if (url != null) {
              _urlController.text = url.toString();
            }
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _urlController,
              focusNode: _focusNodeURL,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              style: theme.textTheme.bodyMedium,
              onSubmitted: _loadUrl,
              canRequestFocus: true,
              selectAllOnFocus: true,
              autocorrect: false,
              enableSuggestions: false,
              onTap: () {
                if (!_alreadyFocusedURL) {
                  _alreadyFocusedURL = true;
                  if (_urlController.text.isNotEmpty) {
                    _urlController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _urlController.text.length,
                    );
                  }
                }
              },
              onTapOutside: (_) {
                _alreadyFocusedURL = false;
                FocusScope.of(context).unfocus();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  tooltip: 'Go',
                  onPressed: () => _loadUrl(_urlController.text),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3.0),
          child: (_isLoading && _progress < 100)
              ? LinearProgressIndicator(
                  value: _progress / 100.0,
                  minHeight: 3.0,
                )
              : const SizedBox(height: 3.0),
        ),
      ),
      body: _buildWebViewBody(context),
      floatingActionButton: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          // Genera 3 oscilaciones completas de izquierda a derecha (amplitud de 6px)
          final double offset =
              math.sin(_shakeController.value * math.pi * 6) * 6;

          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
        child: FilledButton.tonalIcon(
          onPressed: _isCapturing ? null : _captureCookies,
          icon: _isCapturing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cookie),
          label: const Text('Save Cookies'),
        ),
      ),
      persistentFooterButtons: [
        DropdownMenu<String>(
          width: 155,
          menuHeight: 260,
          initialSelection: _defaultSearchEngineURL,
          label: const Text('Shortcuts', style: TextStyle(fontSize: 12)),
          enableFilter: true,
          enableSearch: true,
          textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          trailingIcon: const Icon(Icons.arrow_drop_down, size: 18),
          selectedTrailingIcon: const Icon(Icons.arrow_drop_up, size: 18),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            isDense: true,
            constraints: const BoxConstraints(maxHeight: 34, minHeight: 34),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownMenuEntries: [
            DropdownMenuEntry<String>(
              label: _defaultSearchEngineName,
              value: _defaultSearchEngineURL,
              trailingIcon: _defaultSearchEngineIcon,
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            DropdownMenuEntry<String>(
              label: 'Youtube',
              value: 'https://youtube.com',
              trailingIcon: const FaIcon(
                FontAwesomeIcons.youtube,
                color: Colors.red,
              ),
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            DropdownMenuEntry<String>(
              label: 'TikTok',
              value: 'https://tiktok.com',
              trailingIcon: const FaIcon(
                FontAwesomeIcons.tiktok,
                color: Colors.black,
              ),
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            DropdownMenuEntry<String>(
              label: 'Twitch',
              value: 'https://twitch.tv',
              trailingIcon: const FaIcon(
                FontAwesomeIcons.twitch,
                color: Colors.purple,
              ),
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            DropdownMenuEntry<String>(
              label: 'DailyMotion',
              value: 'https://dailymotion.com',
              trailingIcon: const FaIcon(
                FontAwesomeIcons.dailymotion,
                color: Colors.orange,
              ),
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            DropdownMenuEntry<String>(
              label: 'Vimeo',
              value: 'https://vimeo.com',
              trailingIcon: const FaIcon(
                FontAwesomeIcons.vimeo,
                color: Colors.blueAccent,
              ),
              style: MenuItemButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          onSelected: (value) {
            if (value != null) {
              _shortcutController.text = value;
              _loadUrl(value);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _canGoBack ? () => _webViewController?.goBack() : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            minimumSize: const Size(10, 10),
            fixedSize: const Size(28, 28),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'Forward',
          onPressed: _canGoForward
              ? () => _webViewController?.goForward()
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            minimumSize: const Size(10, 10),
            fixedSize: const Size(28, 28),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () => _webViewController?.reload(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            minimumSize: const Size(10, 10),
            fixedSize: const Size(28, 28),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
