import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Constantes y Dominios
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

// Widgets Perezosos
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class QuickShareOverlay extends StatefulWidget {
  const QuickShareOverlay({super.key});

  @override
  State<QuickShareOverlay> createState() => _QuickShareOverlayState();
}

class _QuickShareOverlayState extends State<QuickShareOverlay> {
  bool _isReady = false;
  String _url = '';
  late DownloadOptions _opts;

  // Estados visuales de la UI
  bool _isSending = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _initListener();
  }

  void _initListener() {
    FlutterOverlayWindow.overlayListener.listen((event) async {
      if (event is Map && mounted) {
        final url = event['url'];
        var incomingOpts = DownloadOptions.fromJson(
          Map<String, dynamic>.from(event['options']),
        );

        // =====================================================================
        // MEMORIA DEL OVERLAY: Sobrescribimos con las últimas elecciones locales
        // =====================================================================
        final prefs = await SharedPreferences.getInstance();

        // 1. Audio / Video (Booleano)
        final extractAudio = prefs.getBool('ov_extractAudio');
        if (extractAudio != null) {
          incomingOpts = incomingOpts.copyWith(extractAudio: extractAudio);
        }

        // 2. Formato de Audio (Enum)
        final audioFmtName = prefs.getString('ov_audioFormat');
        if (audioFmtName != null) {
          final aFmt = AudioFormat.values.firstWhere(
            (e) => e.name == audioFmtName,
            orElse: () => incomingOpts.audioFormat,
          );
          incomingOpts = incomingOpts.copyWith(audioFormat: aFmt);
        }

        // 3. Formato de Video (Enum MergeOutputFormat)
        final videoFmtName = prefs.getString('ov_mergeOutputFormat');
        if (videoFmtName != null) {
          final vFmt = MergeOutputFormat.values.firstWhere(
            (e) => e.name == videoFmtName,
            orElse: () => incomingOpts.mergeOutputFormat,
          );
          incomingOpts = incomingOpts.copyWith(mergeOutputFormat: vFmt);
        }

        // 4. Resolución de Video
        final vidResType = prefs.getString('ov_videoResType');
        final vidResVal = prefs.getString('ov_videoResVal');
        if (vidResType != null) {
          final vOpt = VideoOption.values.firstWhere(
            (e) => e.name == vidResType,
            orElse: () => incomingOpts.videoResolution,
          );
          incomingOpts = incomingOpts.copyWith(
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
            orElse: () => incomingOpts.audioLanguage,
          );
          incomingOpts = incomingOpts.copyWith(
            audioLanguage: aOpt,
            audioLanguageCode: audLangVal,
          );
        }

        // 6. Idiomas de Subtítulos
        final subLangs = prefs.getStringList('ov_subLangs');
        if (subLangs != null) {
          incomingOpts = incomingOpts.copyWith(subLangs: subLangs);
        }

        // Actualizamos la UI
        setState(() {
          _url = url;
          _opts = incomingOpts;
          _isReady = true;
        });
      }
    });
  }

  Future<void> _sendAndClose() async {
    setState(() => _isSending = true);

    // 1. Enviamos el mensaje al Isolate principal (share_wrapper lo recibe)
    await FlutterOverlayWindow.shareData({
      "action": "START_DOWNLOAD",
      "url": _url,
      "options": _opts.toJson(),
    });

    // 2. Transición a estado de Éxito
    setState(() {
      _isSending = false;
      _showSuccess = true;
    });

    // 3. Esperamos para que el usuario disfrute la palomita verde y destruimos la ventana
    await Future.delayed(const Duration(milliseconds: 1200));
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // GESTO PARA CERRAR: Si el usuario toca el fondo borroso, se cierra.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => FlutterOverlayWindow.closeOverlay(),
              child: Container(color: Colors.transparent),
            ),
          ),

          // EL PANEL GLASSMORPHISM (Alineado abajo)
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                  ),
                  // Mágico: Esto levanta el panel si el teclado nativo aparece
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _showSuccess
                        ? _buildSuccessView()
                        : _buildFormView(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // VISTA 1: FORMULARIO DINÁMICO
  // =========================================================================
  Widget _buildFormView() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(), // Evita scroll innecesario
      child: Column(
        mainAxisSize: MainAxisSize.min, // Wrap Content
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pill Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
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
            _url,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // --- SEGMENTED BUTTON GIGANTE (VIDEO / AUDIO) ---
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text(
                  'Descargar Video',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: Icon(Icons.movie),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  'Descargar Audio',
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

          // --- CONTENIDO DINÁMICO ---
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

          // --- BOTÓN FINAL ---
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

  // =========================================================================
  // VISTA 2: MENSAJE DE ÉXITO
  // =========================================================================
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

  // =========================================================================
  // WIDGETS AUXILIARES PARA PREPARAR LAS LISTAS
  // =========================================================================

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
