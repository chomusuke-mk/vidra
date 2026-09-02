import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:vidra/features/downloads/presentation/widgets/download_action_buttons.dart';

import '../../data/cookie_exporter.dart';

/// Full-screen in-app WebView screen / dialog that enables users to browse,
/// log in to authenticated websites, and automatically capture/export session and
/// persistent cookies per-domain into the save directory.

const _defaultSearchEngineURL = 'https://search.brave.com';
const _defaultSearchEngineName = 'Brave';
const _defaultSearchEngineIcon = FaIcon(
  FontAwesomeIcons.brave,
  color: Colors.deepOrange,
);

class InAppWebViewScreen extends StatefulWidget {
  final String url;
  final String saveCookiesPath;
  final bool showActionButtons;

  const InAppWebViewScreen({
    super.key,
    required this.url,
    required this.saveCookiesPath,
    this.showActionButtons = false,
  });

  /// Returns `true` if the current platform supports the In-App WebView, `false` otherwise.
  static bool get isWebViewSupported =>
      InAppWebViewPlatform.instance != null &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  /// Displays the [InAppWebViewScreen] as a full-screen dialog route and
  /// returns the absolute path of the generated cookie file or directory, or `null` if dismissed.
  static Future<String?> show(
    BuildContext context,
    String saveCookiesPath, {
    String? url,
    bool showActionButtons = false,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InAppWebViewScreen(
          url: url ?? _defaultSearchEngineURL,
          saveCookiesPath: saveCookiesPath,
          showActionButtons: showActionButtons,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Normalizes a given URL string, prepending `https://` if the protocol scheme is missing.
  static String normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '$_defaultSearchEngineURL/search?q=';
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
      return trimmed;
    }
    if (trimmed.contains('.') ||
        trimmed.contains(':') ||
        trimmed == 'localhost') {
      return 'https://$trimmed';
    }
    return '$_defaultSearchEngineURL/search?q=${Uri.encodeComponent(trimmed)}';
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

    if (InAppWebViewScreen.isWebViewSupported) {
      _periodicCookieSaveTimer = Timer.periodic(const Duration(seconds: 5), (
        _,
      ) {
        if (mounted && _webViewController != null) {
          _extractAndSaveCookiesForCurrentDomain();
        }
      });
    }
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
    if (!InAppWebViewScreen.isWebViewSupported) {
      return;
    }
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

  void _showManageCookiesSheet(BuildContext context) {
    final locale = context.read<LocaleController>().localeStrings;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final directory = Directory(widget.saveCookiesPath.trim());
            final List<File> files = widget.saveCookiesPath.trim().isNotEmpty
                ? CookieExporter.getSavedCookieFiles(directory: directory)
                : <File>[];

            final theme = Theme.of(context);
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            locale.wvManageCookies,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: locale.sdClose,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (files.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cookie_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                locale.sNoCookiesFound,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        for (int i = 0; i < files.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Builder(
                            builder: (context) {
                              final file = files[i];
                              final fileName = p.basename(file.path);
                              int fileSize = 0;
                              try {
                                fileSize = file.lengthSync();
                              } catch (_) {}

                              final sizeStr = fileSize >= 1024 * 1024
                                  ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
                                  : (fileSize >= 1024
                                        ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
                                        : '$fileSize B');

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.cookie_outlined),
                                title: Text(
                                  fileName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  sizeStr,
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await CookieExporter.deleteCookieFileAndAssociatedCookies(
                                      file,
                                    );
                                    setModalState(() {});
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWebViewBody(BuildContext context, AppStringKey locale) {
    if (!InAppWebViewScreen.isWebViewSupported) {
      //return const SizedBox.shrink();
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(locale.wvNotSupported),
            SizedBox(height: 8),
            Text(
              '(╥﹏╥)',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withAlpha(100),
              ),
            ),
          ],
        ),
      );
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
        body: _buildWebViewBody(context, locale),
        floatingActionButton: widget.showActionButtons
            ? DownloadActionButtons(
                getUrl: () => _urlController.text,
                onDownloadSuccess: () {},
                isMainScreen: false,
              )
            : null,
        persistentFooterButtons: [
          Wrap(
            spacing: 4,
            clipBehavior: Clip.none,
            runSpacing: 0,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: locale.wvManageCookies,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(10, 10),
                  fixedSize: const Size(28, 28),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'manage_cookies',
                    child: Text(locale.wvManageCookies),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'manage_cookies') {
                    _showManageCookiesSheet(context);
                  }
                },
              ),
              DropdownMenu<String>(
                width: 130,
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
                  constraints: const BoxConstraints(
                    maxHeight: 34,
                    minHeight: 34,
                    maxWidth: 130,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
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
                    label: 'Music',
                    value: 'https://music.youtube.com',
                    trailingIcon: const FaIcon(
                      FontAwesomeIcons.solidCirclePlay,
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
                    label: 'Facebook',
                    value: 'https://facebook.com',
                    trailingIcon: const FaIcon(
                      FontAwesomeIcons.facebook,
                      color: Colors.blueAccent,
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
                onPressed: _canGoBack
                    ? () => _webViewController?.goBack()
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
            ],
          ),
        ],
      ),
    );
  }
}
