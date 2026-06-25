import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// Importa tus constantes puras (no dependientes de Provider)
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

// Importa tus widgets perezosos
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class QuickShareOverlay extends StatefulWidget {
  const QuickShareOverlay({super.key});

  @override
  State<QuickShareOverlay> createState() => _QuickShareOverlayState();
}

class _QuickShareOverlayState extends State<QuickShareOverlay> {
  @override
  void initState() {
    super.initState();
    // Escuchar el puente
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && mounted) {
        final url = event['url'];
        final opts = DownloadOptions.fromJson(
          Map<String, dynamic>.from(event['options']),
        );
        // Lanzamos el BottomSheet tan pronto llegan los datos
        _showBottomSheet(url, opts);
      }
    });
  }

  Future<void> _showBottomSheet(String url, DownloadOptions opts) async {
    // showModalBottomSheet nos da GRATIS: Animación, oscurecer fondo, tap-to-close y swipe-to-close.
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _QuickShareBottomSheetContent(url: url, initialOpts: opts),
    );

    // Esta línea se ejecuta ÚNICAMENTE cuando el BottomSheet termina de cerrarse y su animación hacia abajo finaliza.
    // Destruimos la ventana del sistema.
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    // La ventana madre es 100% invisible
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

  @override
  void initState() {
    super.initState();
    _opts = widget.initialOpts;
  }

  void _sendAndClose() {
    // 1. Enviamos el mensaje al hilo principal
    FlutterOverlayWindow.shareData({
      "action": "START_DOWNLOAD",
      "url": widget.url,
      "options": _opts.toJson(),
    });

    // 2. Cerramos el BottomSheet (Esto dispara la animación hacia abajo y luego cierra el Overlay total)
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Audio
    final List<String> audioOptionsFlat = [
      'defaultOption',
      'bestaudio',
      ...languagesCodes,
    ];
    String currentAudioVal = 'defaultOption';
    if (_opts.audioLanguage == AudioOption.bestaudio) {
      currentAudioVal = 'bestaudio';
    } else if (_opts.audioLanguage == AudioOption.language &&
        _opts.audioLanguageCode != null) {
      currentAudioVal = _opts.audioLanguageCode!;
    }
    if (!audioOptionsFlat.contains(currentAudioVal)) {
      currentAudioVal = 'defaultOption';
    }
    // Video
    final List<String> videoResolutionFlat = [
      'defaultOption',
      'bestvideo',
      ...videoResolutions,
    ];
    String currentVideoVal = 'defaultOption';
    if (_opts.videoResolution == VideoOption.bestvideo) {
      currentVideoVal = 'bestvideo';
    } else if (_opts.videoResolution == VideoOption.resolution &&
        _opts.videoResolutionValue != null) {
      currentVideoVal = _opts.videoResolutionValue!;
    }
    if (!videoResolutionFlat.contains(currentVideoVal)) {
      currentVideoVal = 'defaultOption';
    }
    // Subs
    final List<String> subSuggestions = languagesCodes
        .map((code) => '$code - ${languagesEndonyms[code] ?? code}')
        .toList();
    final List<String> visualSubList = _opts.subLangs
        .map((code) => '$code - ${languagesEndonyms[code] ?? code}')
        .toList();

    return Container(
      // Padding mágico para que el teclado levante el panel sin ocultar el contenido
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + 16, // MAGIA DEL TECLADO
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Wrap Content de la altura
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Quick Download',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.pop(context), // Cierra con animación
                  ),
                ],
              ),
              Text(
                widget.url,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(),

              // 1. Extraer Audio (Switch)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Extract Audio'),
                value: _opts.extractAudio,
                onChanged: (val) =>
                    setState(() => _opts = _opts.copyWith(extractAudio: val)),
              ),
              const SizedBox(height: 8),

              // 2. Video Resolution
              const Text(
                'Video Resolution',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              LazyDropdown<String>(
                value: currentVideoVal,
                items: videoResolutionFlat,
                labelBuilder: (val) {
                  if (val == 'defaultOption') return 'Default';
                  if (val == 'bestvideo') return 'Best Video';
                  return resolutionLabels[val] ?? val;
                },
                onChanged: (val) {
                  if (val == 'defaultOption') {
                    setState(
                      () => _opts = _opts.copyWith(
                        videoResolution: VideoOption.defaultOption,
                      ),
                    );
                  } else if (val == 'bestvideo') {
                    setState(
                      () => _opts = _opts.copyWith(
                        videoResolution: VideoOption.bestvideo,
                      ),
                    );
                  } else {
                    setState(
                      () => _opts = _opts.copyWith(
                        videoResolution: VideoOption.resolution,
                        videoResolutionValue: val,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),

              // 3. Audio Language
              const Text(
                'Audio Language',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              LazyDropdown<String>(
                value: currentAudioVal,
                items: audioOptionsFlat,
                enableSearch: true,
                labelBuilder: (val) {
                  if (val == 'defaultOption') return 'Default';
                  if (val == 'bestaudio') return 'Best Audio';
                  return '$val - ${languagesEndonyms[val] ?? val}';
                },
                onChanged: (val) {
                  if (val == 'defaultOption') {
                    setState(
                      () => _opts = _opts.copyWith(
                        audioLanguage: AudioOption.defaultOption,
                      ),
                    );
                  } else if (val == 'bestaudio') {
                    setState(
                      () => _opts = _opts.copyWith(
                        audioLanguage: AudioOption.bestaudio,
                      ),
                    );
                  } else {
                    setState(
                      () => _opts = _opts.copyWith(
                        audioLanguage: AudioOption.language,
                        audioLanguageCode: val,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),

              // 4. Subtitle Languages (LazyList) - AHORA EL TECLADO FUNCIONA
              const Text(
                'Subtitle Languages',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              LazyList(
                value: visualSubList,
                suggestions: subSuggestions,
                label: 'Search language...',
                onChanged: (newList) {
                  final codesToSave = newList
                      .map((item) => item.split(' - ').first.trim())
                      .toList();
                  setState(() => _opts = _opts.copyWith(subLangs: codesToSave));
                },
              ),
              const SizedBox(height: 24),

              // Botón Final
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Download'),
                onPressed: _sendAndClose, // ESTE BOTÓN AHORA VIVE FELIZ
              ),
            ],
          ),
        ),
      ),
    );
  }
}
