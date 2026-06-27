import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Constantes y Dominios
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

// Widgets Perezosos
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class QuickShareOverlay extends StatefulWidget {
  const QuickShareOverlay({super.key});

  @override
  State<QuickShareOverlay> createState() => _QuickShareOverlayState();
}

class _QuickShareOverlayState extends State<QuickShareOverlay> {
  bool _isShowingSheet = false;
  @override
  void initState() {
    super.initState();
    _initListener();
  }

  void _initListener() {
    FlutterOverlayWindow.overlayListener.listen((event) async {
      if (event is Map && mounted && !_isShowingSheet) {
        _isShowingSheet = true;
        debugPrint('🦄 [OVERLAY] Datos recibidos de la UI/Wrapper.');
        final url = event['url'];
        var opts = DownloadOptions.fromJson(
          Map<String, dynamic>.from(event['options']),
        );

        // =====================================================================
        // MEMORIA DEL OVERLAY: Sobrescribimos con las últimas elecciones locales
        // =====================================================================
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();

        // 1. Audio / Video (Booleano)
        final extractAudio = prefs.getBool('ov_extractAudio');
        if (extractAudio != null) {
          opts = opts.copyWith(extractAudio: extractAudio);
        }

        // 2. Formato de Audio (Enum)
        final audioFmtName = prefs.getString('ov_audioFormat');
        if (audioFmtName != null) {
          final aFmt = AudioFormat.values.firstWhere(
            (e) => e.name == audioFmtName,
            orElse: () => opts.audioFormat,
          );
          opts = opts.copyWith(audioFormat: aFmt);
        }

        // 3. Formato de Video (Enum MergeOutputFormat)
        final videoFmtName = prefs.getString('ov_mergeOutputFormat');
        if (videoFmtName != null) {
          final vFmt = MergeOutputFormat.values.firstWhere(
            (e) => e.name == videoFmtName,
            orElse: () => opts.mergeOutputFormat,
          );
          opts = opts.copyWith(mergeOutputFormat: vFmt);
        }

        // 4. Resolución de Video
        final vidResType = prefs.getString('ov_videoResType');
        final vidResVal = prefs.getString('ov_videoResVal');
        if (vidResType != null) {
          final vOpt = VideoOption.values.firstWhere(
            (e) => e.name == vidResType,
            orElse: () => opts.videoResolution,
          );
          opts = opts.copyWith(
            videoResolution: vOpt,
            videoResolutionValue: vidResVal,
          );
        }

        // 5. Idioma de Audio
        final audLangType = prefs.getString('ov_audLangType');
        final audLangVal = prefs.getString('ov_audLangVal');
        if (audLangType != null) {
          final aOpt = AudioOption.values.firstWhere(
            (e) => e.name == audLangType,
            orElse: () => opts.audioLanguage,
          );
          opts = opts.copyWith(
            audioLanguage: aOpt,
            audioLanguageCode: audLangVal,
          );
        }

        // 6. Idiomas de Subtítulos
        final subLangs = prefs.getStringList('ov_subLangs');
        if (subLangs != null) {
          opts = opts.copyWith(subLangs: subLangs);
        }

        // Actualizamos la UI
        _showBottomSheet(url, opts);
        _isShowingSheet = false;
      }
    });
  }

  Future<void> _showBottomSheet(String url, DownloadOptions opts) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (context) =>
          _QuickShareBottomSheetContent(url: url, initialOpts: opts),
    );
    // ponytail: Si el usuario toca afuera o desliza para abajo, DESTRUIMOS la ventana invisible.
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.transparent);
  }
}

// ============================================================================
// EL CONTENIDO DEL BOTTOM SHEET
// ============================================================================
class _QuickShareBottomSheetContent extends StatefulWidget {
  final String url;
  final DownloadOptions initialOpts;

  const _QuickShareBottomSheetContent({
    required this.url,
    required this.initialOpts,
  });

  @override
  State<_QuickShareBottomSheetContent> createState() =>
      _QuickShareBottomSheetContentState();
}

class _QuickShareBottomSheetContentState
    extends State<_QuickShareBottomSheetContent> {
  late DownloadOptions _opts;
  bool _isSending = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _opts = widget.initialOpts;
  }

  void _sendAndClose() async {
    setState(() => _isSending = true);

    try {
      debugPrint('🦄 [OVERLAY] Iniciando comunicación directa con Isolate...');

      // EL BYPASS MAGISTRAL: Hablamos directo a la memoria del Isolate del Backend
      final sendPort = IsolateNameServer.lookupPortByName('vidra_backend_port');

      if (sendPort != null) {
        sendPort.send({
          'cmd': 'download',
          'url': widget.url,
          'options': _opts.toJson(),
        });
        debugPrint('🦄 [OVERLAY] ¡Mensaje enviado con éxito al Cerebro!');
        if (mounted) {
          setState(() {
            _isSending = false;
            _showSuccess = true;
          });
        }
        // 3. Esperamos 1 segundo para mostrar el check
        await Future.delayed(const Duration(milliseconds: 1000));
      } else {
        debugPrint(
          '🦄 [OVERLAY] ERROR FATAL: NO SE DEBERÍA HABER LLEGADO AQUÍ!!.',
        );
        throw Exception(
          'No se pudo encontrar el puerto del Isolate. Asegúrate de que la app principal esté corriendo.',
        );
      }
    } catch (e) {
      debugPrint("🦄 [OVERLAY] Error in overlay send: $e");
      ToastUtils.showError(
        'No se pudo enviar la descarga. Intenta abrir la app y volver a intentarlo.',
      );
    }

    // 4. Bajamos el modal visualmente
    if (mounted) Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 300));
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _showSuccess ? _buildSuccessView() : _buildFormView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const Text(
            'Descarga Rápida',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            widget.url,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text(
                  'Video',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: Icon(Icons.movie),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  'Audio',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: Icon(Icons.audiotrack),
              ),
            ],
            selected: {_opts.extractAudio},
            onSelectionChanged: (set) async {
              final val = set.first;
              setState(() => _opts = _opts.copyWith(extractAudio: val));
              final prefs = await SharedPreferences.getInstance();
              prefs.setBool('ov_extractAudio', val);
            },
          ),
          const SizedBox(height: 20),

          if (_opts.extractAudio) ...[
            const Text(
              'Formato de Audio',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            LazyDropdown<AudioFormat>(
              value: _opts.audioFormat,
              items: AudioFormat.values,
              labelBuilder: (m) => m.name.toUpperCase(),
              onChanged: (val) async {
                setState(() => _opts = _opts.copyWith(audioFormat: val));
                final prefs = await SharedPreferences.getInstance();
                prefs.setString('ov_audioFormat', val.name);
              },
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resolución',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildVideoResDropdown(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Formato',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LazyDropdown<MergeOutputFormat>(
                        value: _opts.mergeOutputFormat,
                        items: MergeOutputFormat.values,
                        labelBuilder: (m) => m.name.toUpperCase(),
                        onChanged: (val) async {
                          setState(
                            () =>
                                _opts = _opts.copyWith(mergeOutputFormat: val),
                          );
                          final prefs = await SharedPreferences.getInstance();
                          prefs.setString('ov_mergeOutputFormat', val.name);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Idioma del Audio',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _buildAudioLangDropdown(),
            const SizedBox(height: 12),
            const Text(
              'Idiomas de Subtítulos',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _buildSubtitlesList(),
          ],

          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: FilledButton.icon(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.download),
              label: Text(
                _isSending ? 'Enviando...' : 'Descargar',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _isSending ? null : _sendAndClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 72),
          const SizedBox(height: 16),
          const Text(
            '¡Descarga Agregada!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Puedes seguir navegando.\nVidra se encarga del resto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // --- MÉTODOS DE LAZY DROPDOWNS ---
  Widget _buildVideoResDropdown() {
    final List<String> flatRes = [
      'defaultOption',
      'bestvideo',
      ...videoResolutions,
    ];
    String currentVal = 'defaultOption';
    if (_opts.videoResolution == VideoOption.bestvideo) {
      currentVal = 'bestvideo';
    }
    if (_opts.videoResolution == VideoOption.resolution &&
        _opts.videoResolutionValue != null) {
      currentVal = _opts.videoResolutionValue!;
    }
    if (!flatRes.contains(currentVal)) currentVal = 'defaultOption';

    return LazyDropdown<String>(
      value: currentVal,
      items: flatRes,
      labelBuilder: (val) {
        if (val == 'defaultOption') return 'Por Defecto';
        if (val == 'bestvideo') return 'Mejor Calidad';
        return resolutionLabels[val] ?? val;
      },
      onChanged: (val) async {
        final prefs = await SharedPreferences.getInstance();
        if (val == 'defaultOption') {
          setState(
            () => _opts = _opts.copyWith(
              videoResolution: VideoOption.defaultOption,
            ),
          );
          prefs.setString('ov_videoResType', VideoOption.defaultOption.name);
        } else if (val == 'bestvideo') {
          setState(
            () =>
                _opts = _opts.copyWith(videoResolution: VideoOption.bestvideo),
          );
          prefs.setString('ov_videoResType', VideoOption.bestvideo.name);
        } else {
          setState(
            () => _opts = _opts.copyWith(
              videoResolution: VideoOption.resolution,
              videoResolutionValue: val,
            ),
          );
          prefs.setString('ov_videoResType', VideoOption.resolution.name);
          prefs.setString('ov_videoResVal', val);
        }
      },
    );
  }

  Widget _buildAudioLangDropdown() {
    final List<String> flatAud = [
      'defaultOption',
      'bestaudio',
      ...languagesCodes,
    ];
    String currentVal = 'defaultOption';
    if (_opts.audioLanguage == AudioOption.bestaudio) currentVal = 'bestaudio';
    if (_opts.audioLanguage == AudioOption.language &&
        _opts.audioLanguageCode != null) {
      currentVal = _opts.audioLanguageCode!;
    }
    if (!flatAud.contains(currentVal)) currentVal = 'defaultOption';

    return LazyDropdown<String>(
      value: currentVal,
      items: flatAud,
      enableSearch: true,
      labelBuilder: (val) {
        if (val == 'defaultOption') return 'Por Defecto';
        if (val == 'bestaudio') return 'Mejor Audio';
        return '$val - ${languagesEndonyms[val] ?? val}';
      },
      onChanged: (val) async {
        final prefs = await SharedPreferences.getInstance();
        if (val == 'defaultOption') {
          setState(
            () => _opts = _opts.copyWith(
              audioLanguage: AudioOption.defaultOption,
            ),
          );
          prefs.setString('ov_audLangType', AudioOption.defaultOption.name);
        } else if (val == 'bestaudio') {
          setState(
            () => _opts = _opts.copyWith(audioLanguage: AudioOption.bestaudio),
          );
          prefs.setString('ov_audLangType', AudioOption.bestaudio.name);
        } else {
          setState(
            () => _opts = _opts.copyWith(
              audioLanguage: AudioOption.language,
              audioLanguageCode: val,
            ),
          );
          prefs.setString('ov_audLangType', AudioOption.language.name);
          prefs.setString('ov_audLangVal', val);
        }
      },
    );
  }

  Widget _buildSubtitlesList() {
    final subSuggestions = languagesCodes
        .map((c) => '$c - ${languagesEndonyms[c] ?? c}')
        .toList();
    final visualSubList = _opts.subLangs
        .map((c) => '$c - ${languagesEndonyms[c] ?? c}')
        .toList();

    return LazyList(
      value: visualSubList,
      suggestions: subSuggestions,
      label: 'Buscar idioma...',
      onChanged: (newList) async {
        final codes = newList.map((i) => i.split(' - ').first.trim()).toList();
        setState(() => _opts = _opts.copyWith(subLangs: codes));
        final prefs = await SharedPreferences.getInstance();
        prefs.setStringList('ov_subLangs', codes);
      },
    );
  }
}
