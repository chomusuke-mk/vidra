import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../data/cookie_exporter.dart';

/// Full-screen in-app WebView screen / dialog that enables users to browse,
/// log in to authenticated websites, and automatically capture/export session and
/// persistent cookies per-domain into the save directory.

const _defaultSearchEngineURL = 'https://search.brave.com/search?q=';
const _defaultSearchEngineName = 'Brave';
const _defaultSearchEngineIcon = FaIcon(
  FontAwesomeIcons.brave,
  color: Colors.deepOrange,
);

class InAppWebViewScreen extends StatefulWidget {
  final String url;
  final String saveCookiesPath;

  const InAppWebViewScreen({
    super.key,
    required this.url,
    required this.saveCookiesPath,
  });

  /// Returns `true` if the current platform supports the In-App WebView, `false` otherwise.
  static bool get isWebViewSupported =>
      InAppWebViewPlatform.instance != null &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  /// Displays the [InAppWebViewScreen] as a full-screen dialog route and
  /// returns the absolute path of the generated cookie file or directory, or `null` if dismissed.
  static Future<String?> show(
    BuildContext context,
    String saveCookiesPath, {
    String? url,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InAppWebViewScreen(
          url: url ?? _defaultSearchEngineURL,
          saveCookiesPath: saveCookiesPath,
        ),
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
    if (trimmed.contains('.') ||
        trimmed.contains(':') ||
        trimmed == 'localhost') {
      return 'https://$trimmed';
    }
    return 'https://google.com/search?q=${Uri.encodeComponent(trimmed)}';
  }

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen> {
  InAppWebViewController? _webViewController;
  late final TextEditingController _urlController;
  final TextEditingController _shortcutController = TextEditingController();
  final FocusNode _focusNodeURL = FocusNode();
  bool _alreadyFocusedURL = false;

  bool _isLoading = false;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isSavingCookies = false;
  bool _pendingSave = false;
  WebUri? _pendingSaveUri;
  String? _lastExtractedHost;
  Timer? _periodicCookieSaveTimer;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: InAppWebViewScreen.normalizeUrl(widget.url),
    );
    _focusNodeURL.addListener(() {
      if (!_focusNodeURL.hasFocus) {
        _alreadyFocusedURL = false;
      }
    });

    _periodicCookieSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _webViewController != null) {
        _extractAndSaveCookiesForCurrentDomain();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final locale = context.read<LocaleController>().localeStrings;
          final toastMessage = locale.wvBrowseToGenerateCookies;
          ToastUtils.showInfo(toastMessage);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _periodicCookieSaveTimer?.cancel();
    _periodicCookieSaveTimer = null;
    _focusNodeURL.dispose();
    _urlController.dispose();
    _shortcutController.dispose();
    super.dispose();
  }

  void _loadUrl(String rawUrl) {
    final normalized = InAppWebViewScreen.normalizeUrl(rawUrl);
    _urlController.text = normalized;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(normalized)),
    );
  }

  /// Automatically extracts and persists Netscape cookies for the current domain.
  Future<void> _extractAndSaveCookiesForCurrentDomain([
    WebUri? currentUri,
  ]) async {
    if (_isSavingCookies) {
      _pendingSave = true;
      _pendingSaveUri = currentUri;
      return;
    }
    _isSavingCookies = true;
    try {
      final WebUri? currentWebUri =
          currentUri ?? await _webViewController?.getUrl();
      final String fallbackUrl = InAppWebViewScreen.normalizeUrl(
        _urlController.text,
      );
      final Uri effectiveUri =
          currentWebUri?.uriValue ?? Uri.tryParse(fallbackUrl) ?? Uri();

      final String host = effectiveUri.host.isNotEmpty
          ? effectiveUri.host
          : (currentWebUri?.host ?? '');

      if (host.isNotEmpty && host != 'about:blank') {
        _lastExtractedHost = host;

        final cookieManager = CookieManager.instance();
        final List<Cookie> cookies = await cookieManager.getCookies(
          url: WebUri(effectiveUri.toString()),
        );

        if (cookies.isNotEmpty && widget.saveCookiesPath.trim().isNotEmpty) {
          debugPrint('Auto-saving ${cookies.length} cookies for domain: $host');
          await CookieExporter.saveDomainCookies(
            cookies,
            domain: host,
            directory: Directory(widget.saveCookiesPath),
          );
        } else {
          debugPrint('No cookies found for domain: $host');
        }
      }
    } catch (e) {
      debugPrint('Error in auto-saving cookies: $e');
    } finally {
      _isSavingCookies = false;
      if (_pendingSave) {
        final nextUri = _pendingSaveUri;
        _pendingSave = false;
        _pendingSaveUri = null;
        unawaited(_extractAndSaveCookiesForCurrentDomain(nextUri));
      }
    }
  }

  Widget _buildWebViewBody(BuildContext context) {
    if (InAppWebViewPlatform.instance == null) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(InAppWebViewScreen.normalizeUrl(widget.url)),
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
        if (url != null &&
            url.host.isNotEmpty &&
            url.host != _lastExtractedHost) {
          unawaited(_extractAndSaveCookiesForCurrentDomain(url));
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
        await _extractAndSaveCookiesForCurrentDomain(url);
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
        if (url != null &&
            url.host.isNotEmpty &&
            url.host != _lastExtractedHost) {
          unawaited(_extractAndSaveCookiesForCurrentDomain(url));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locale = context.read<LocaleController>().localeStrings;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        unawaited(_extractAndSaveCookiesForCurrentDomain());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: locale.sdClose,
            onPressed: () async {
              await _extractAndSaveCookiesForCurrentDomain();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
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
                    tooltip: locale.wvGo,
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
        persistentFooterButtons: [
          DropdownMenu<String>(
            width: 155,
            menuHeight: 260,
            initialSelection: _defaultSearchEngineURL,
            label: Text(
              locale.wvShortcuts,
              style: const TextStyle(fontSize: 12),
            ),
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
            tooltip: locale.wvBack,
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
            tooltip: locale.wvForward,
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
            tooltip: locale.wvRefresh,
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
      ),
    );
  }
}
