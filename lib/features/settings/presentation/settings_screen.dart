import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';
import 'package:vidra/shared/widgets/lazy_map.dart';
import 'package:vidra/shared/widgets/lazy_text_field.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/shared/widgets/settings_row.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';
import 'settings_controller.dart';

enum SettingCategory { general, network, video, download }

class _SettingDef {
  final String title;
  final String? description;
  final SettingCategory category;
  final ControllerType type;
  final Widget Function(BuildContext, SettingsController) controlBuilder;

  _SettingDef({
    required this.title,
    this.description,
    required this.category,
    required this.type,
    required this.controlBuilder,
  });
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSearching = false;
  String _searchQuery = '';
  int _selectedIndex = 0; // Para el NavigationRail (pantallas bajas)

  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) TutorialUtils.showSettingsTutorial(context);
      });
    });
  }

  // ===========================================================================
  // LA LISTA MAESTRA DE CONFIGURACIONES
  // ===========================================================================
  List<_SettingDef> _getAllSettings(
    SettingsController ctrl,
    AppStringKey locale,
  ) {
    final opts = ctrl.downloadOptions;
    // audio_options------------------
    final List<String> audioOptionsFlat = [
      'defaultOption',
      'bestaudio',
      ...languagesCodes,
    ];
    String currentAudioVal = 'defaultOption';
    if (opts.audioLanguage == AudioOption.bestaudio) {
      currentAudioVal = 'bestaudio';
    } else if (opts.audioLanguage == AudioOption.language &&
        opts.audioLanguageCode != null) {
      currentAudioVal = opts.audioLanguageCode!;
    }
    if (!audioOptionsFlat.contains(currentAudioVal)) {
      currentAudioVal = 'defaultOption';
    }
    // video_resolution-----------------
    final List<String> videoResolutionFlat = [
      'defaultOption',
      'bestvideo',
      ...videoResolutions,
    ];
    String currentVideoVal = 'defaultOption';
    if (opts.videoResolution == VideoOption.bestvideo) {
      currentVideoVal = 'bestvideo';
    } else if (opts.videoResolution == VideoOption.resolution &&
        opts.videoResolutionValue != null) {
      currentVideoVal = opts.videoResolutionValue!;
    }
    if (!videoResolutionFlat.contains(currentVideoVal)) {
      currentVideoVal = 'defaultOption';
    }

    return [
      // --- GENERAL ---
      _SettingDef(
        title: locale.sThemeApp,
        description: locale.sThemeAppDesc,
        category: SettingCategory.general,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<ThemeMode>(
          value: s.appTheme,
          items: ThemeMode.values,
          labelBuilder: (t) => t.name.toUpperCase(),
          onChanged: (val) => s.setAppTheme(val),
        ),
      ),
      _SettingDef(
        title: locale.sAppLanguage,
        description: locale.sAppLanguageDesc,
        category: SettingCategory.general,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<String>(
          value: s.appLanguage,
          items: languagesCodes,
          enableSearch: true,
          labelBuilder: (t) => languagesEndonyms[t] ?? t.toUpperCase(),
          onChanged: (val) => s.setAppLanguage(val),
        ),
      ),
      _SettingDef(
        title: locale.sVideoResolution,
        description: locale.sVideoResolutionDesc,
        category: SettingCategory.general,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<String>(
          value: currentVideoVal,
          items: videoResolutionFlat,
          labelBuilder: (val) {
            if (val == 'defaultOption') return locale.sDefault;
            if (val == 'bestvideo') return locale.sBest;
            return resolutionLabels[val] ?? val;
          },
          onChanged: (val) {
            if (val == 'defaultOption') {
              s.updateDownloadOptions(
                opts.copyWith(videoResolution: VideoOption.defaultOption),
              );
            } else if (val == 'bestvideo') {
              s.updateDownloadOptions(
                opts.copyWith(videoResolution: VideoOption.bestvideo),
              );
            } else {
              s.updateDownloadOptions(
                opts.copyWith(
                  videoResolution: VideoOption.resolution,
                  videoResolutionValue: val,
                ),
              );
            }
          },
        ),
      ),
      _SettingDef(
        title: locale.sAudioLanguage,
        description: locale.sAudioLanguageDesc,
        category: SettingCategory.general,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<String>(
          value: currentAudioVal,
          items: audioOptionsFlat,
          enableSearch: true,
          labelBuilder: (val) {
            // Mapeamos los Strings planos a los textos bonitos para el usuario
            if (val == 'defaultOption') return locale.sDefault;
            if (val == 'bestaudio') return locale.sBest;

            // Si es un código, armamos "es - Español"
            final langName = languagesEndonyms[val] ?? val;
            return '$val - $langName';
          },
          onChanged: (val) {
            if (val == 'defaultOption') {
              s.updateDownloadOptions(
                opts.copyWith(audioLanguage: AudioOption.defaultOption),
              );
            } else if (val == 'bestaudio') {
              s.updateDownloadOptions(
                opts.copyWith(audioLanguage: AudioOption.bestaudio),
              );
            } else {
              s.updateDownloadOptions(
                opts.copyWith(
                  audioLanguage: AudioOption.language,
                  audioLanguageCode:
                      val, // Este campo es el que viaja al JSON de Python
                ),
              );
            }
          },
        ),
      ),
      _SettingDef(
        title: locale.sSubLangs,
        description: locale.sSubLangsDesc,
        category: SettingCategory.general,
        type: ControllerType
            .complex, // Salta a la línea inferior para tener todo el ancho
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;

          // 1. Armamos las sugerencias amigables para el usuario (ej: "all", "es - Español")
          final List<String> friendlySuggestions = [
            ...languagesCodes.map((code) {
              final name = languagesEndonyms[code] ?? code;
              return '$code - $name';
            }),
          ];

          // 2. Convertimos los códigos guardados ('es') al formato visual del Chip ('es - Español')
          final visualList = opts.subLangs.map((code) {
            final name = languagesEndonyms[code] ?? code;
            return '$code - $name';
          }).toList();

          return LazyList(
            value: visualList,
            suggestions: friendlySuggestions,
            label: locale.sSearchLang,
            onChanged: (newList) {
              // 3. Cuando el usuario añade/borra, extraemos solo el código original ("es - Español" -> "es")
              final codesToSave = newList.map((item) {
                // Si el item tiene " - ", cortamos y tomamos la primera parte
                return item.split(' - ').first.trim();
              }).toList();

              s.updateDownloadOptions(opts.copyWith(subLangs: codesToSave));
            },
          );
        },
      ),
      _SettingDef(
        title: locale.sExtractAudio,
        description: locale.sExtractAudioDesc,
        category: SettingCategory.general,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.extractAudio,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(extractAudio: val)),
        ),
      ),
      _SettingDef(
        title: locale.sPlaylist,
        description: locale.sPlaylistDesc,
        category: SettingCategory.general,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.playlist,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(playlist: val)),
        ),
      ),
      _SettingDef(
        title: locale.sSponsorblockMark,
        description: locale.sSponsorblockMarkDesc,
        category: SettingCategory.general,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final suggestions = SponsorblockCategory.values
              .map((e) => e.name)
              .toList();
          final visualList = opts.sponsorblockMark.map((e) => e.name).toList();
          return LazyList(
            value: visualList,
            suggestions: suggestions,
            label: locale.sSearchCategory,
            onChanged: (newList) {
              final newEnums = newList.map((item) {
                return SponsorblockCategory.values.firstWhere(
                  (e) => e.name == item,
                  orElse: () => SponsorblockCategory.sponsor,
                );
              }).toList();
              s.updateDownloadOptions(
                opts.copyWith(sponsorblockMark: newEnums),
              );
            },
          );
        },
      ),
      _SettingDef(
        title: locale.sSponsorblockRemove,
        description: locale.sSponsorblockRemoveDesc,
        category: SettingCategory.general,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final suggestions = SponsorblockCategory.values
              .map((e) => e.name)
              .toList();
          final visualList = opts.sponsorblockRemove
              .map((e) => e.name)
              .toList();
          return LazyList(
            value: visualList,
            suggestions: suggestions,
            label: locale.sSearchCategory,
            onChanged: (newList) {
              final newEnums = newList.map((item) {
                return SponsorblockCategory.values.firstWhere(
                  (e) => e.name == item,
                  orElse: () => SponsorblockCategory.sponsor,
                );
              }).toList();
              s.updateDownloadOptions(
                opts.copyWith(sponsorblockRemove: newEnums),
              );
            },
          );
        },
      ),
      // --- NETWORK ---
      _SettingDef(
        title: locale.sProxy,
        description: locale.sProxyDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.proxy,
          hint: 'socks5://127.0.0.1:1080',
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(proxy: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sSocketTimeout,
        description: locale.sSocketTimeoutDesc,
        category: SettingCategory.network,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.infiniteSocketTimeout;
          return Row(
            children: [
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(infiniteSocketTimeout: !val),
                ),
              ),
              const SizedBox(width: 16),
              if (isEnabled)
                Expanded(
                  child: LazyTextField(
                    value: opts.socketTimeout?.toString() ?? '',
                    isNumeric: true,
                    hint: '666',
                    onChanged: (val) => s.updateDownloadOptions(
                      opts.copyWith(socketTimeout: int.tryParse(val)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sSourceAddress,
        description: locale.sSourceAddressDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.sourceAddress,
          hint: '192.168.1.100',
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(sourceAddress: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sImpersonate,
        description: locale.sImpersonateDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.impersonate,
          hint: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(impersonate: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sForceIpv4,
        description: locale.sForceIpv4Desc,
        category: SettingCategory.network,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.forceIpv4,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(forceIpv4: val)),
        ),
      ),
      _SettingDef(
        title: locale.sForceIpv6,
        description: locale.sForceIpv6Desc,
        category: SettingCategory.network,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.forceIpv6,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(forceIpv6: val)),
        ),
      ),
      _SettingDef(
        title: locale.sEnableFileUrls,
        description: locale.sEnableFileUrlsDesc,
        category: SettingCategory.network,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.enableFileUrls,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(enableFileUrls: val)),
        ),
      ),
      _SettingDef(
        title: locale.sGeoVerificationProxy,
        description: locale.sGeoVerificationProxyDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.geoVerificationProxy,
          hint: 'socks5://127.0.0.1:1080',
          onChanged: (val) => s.updateDownloadOptions(
            opts.copyWith(geoVerificationProxy: val.trim()),
          ),
        ),
      ),
      _SettingDef(
        title: locale.sXff,
        description: locale.sXffDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.xff,
          hint: '198.51.100.1',
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(xff: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sPreferInsecure,
        description: locale.sPreferInsecureDesc,
        category: SettingCategory.network,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.preferInsecure,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(preferInsecure: val)),
        ),
      ),
      _SettingDef(
        title: locale.sAddHeaders,
        description: locale.sAddHeadersDesc,
        category: SettingCategory.network,
        type: ControllerType
            .complex, // Se alinea debajo para darle todo el ancho disponible
        controlBuilder: (c, s) => LazyMap(
          value: opts.addHeaders,
          // Le regalamos al usuario las claves más comunes para que no tenga que escribirlas
          keySuggestions: const [
            'User-Agent',
            'Referer',
            'Accept',
            'Accept-Language',
            'Authorization',
            'Origin',
          ],
          onChanged: (newMap) =>
              s.updateDownloadOptions(opts.copyWith(addHeaders: newMap)),
        ),
      ),
      _SettingDef(
        title: locale.sCookies,
        description: locale.sCookiesDesc,
        category: SettingCategory.network,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.disableCookies;
          return Row(
            children: [
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(disableCookies: !val),
                ),
              ),
              const SizedBox(width: 16),
              if (isEnabled)
                Expanded(
                  child: LazyTextField(
                    value: opts.cookies ?? '',
                    hint: locale.sSelectFile,
                    pickFile: true,
                    onChanged: (val) => s.updateDownloadOptions(
                      opts.copyWith(cookies: val.trim()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sCookiesFromBrowser,
        description: locale.sCookiesFromBrowserDesc,
        category: SettingCategory.network,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.disableCookiesFromBrowser;
          return Row(
            children: [
              // 1. Switch maestro para encender/apagar la extracción
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(
                    disableCookiesFromBrowser: !val,
                    // Si el usuario lo enciende y no había un navegador seleccionado,
                    // le asignamos Chrome como valor por defecto seguro.
                    cookiesFromBrowser: val && opts.cookiesFromBrowser == null
                        ? Browser.chrome
                        : opts.cookiesFromBrowser,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 2. Dropdown de selección (Solo visible si el Switch está encendido)
              if (isEnabled)
                Expanded(
                  child: LazyDropdown<Browser>(
                    // Muestra el valor guardado, o chrome por defecto
                    value: opts.cookiesFromBrowser ?? Browser.chrome,
                    items: Browser.values,
                    // Formateamos "chrome" a "CHROME" visualmente
                    labelBuilder: (b) => b.name.toUpperCase(),
                    onChanged: (val) => s.updateDownloadOptions(
                      opts.copyWith(cookiesFromBrowser: val),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sUsername,
        description: locale.sUsernameDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.username,
          hint: locale.sNotConfigured,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(username: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sPassword,
        description: locale.sPasswordDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.password,
          hint: locale.sNotConfigured,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(password: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sTwofactor,
        description: locale.sTwofactorDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.twofactor,
          hint: locale.sNotConfigured,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(twofactor: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sVideoPassword,
        description: locale.sVideoPasswordDesc,
        category: SettingCategory.network,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.videoPassword,
          hint: locale.sNotConfigured,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(videoPassword: val.trim())),
        ),
      ),
      // --- VIDEO ---
      _SettingDef(
        title: locale.sMergeOutputFormat,
        description: locale.sMergeOutputFormatDesc,
        category: SettingCategory.video,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<MergeOutputFormat>(
          value: opts.mergeOutputFormat,
          items: MergeOutputFormat.values,
          labelBuilder: (m) => m.name.toUpperCase(),
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(mergeOutputFormat: val)),
        ),
      ),
      _SettingDef(
        title: locale.sAudioFormat,
        description: locale.sAudioFormatDesc,
        category: SettingCategory.video,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<AudioFormat>(
          value: opts.audioFormat,
          items: AudioFormat.values,
          labelBuilder: (m) => m.name.toUpperCase(),
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(audioFormat: val)),
        ),
      ),
      _SettingDef(
        title: locale.sSubFormat,
        description: locale.sSubFormatDesc,
        category: SettingCategory.video,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<SubtitleFormat>(
          value: opts.subFormat,
          items: SubtitleFormat.values,
          labelBuilder: (m) => m.name.toUpperCase(),
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(subFormat: val)),
        ),
      ),
      _SettingDef(
        title: locale.sVideoMultistreams,
        description: locale.sVideoMultistreamsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.videoMultistreams,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(videoMultistreams: val)),
        ),
      ),
      _SettingDef(
        title: locale.sAudioMultistreams,
        description: locale.sAudioMultistreamsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.audioMultistreams,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(audioMultistreams: val)),
        ),
      ),
      _SettingDef(
        title: locale.sAudioQuality,
        description: locale.sAudioQualityDesc,
        category: SettingCategory.video,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.audioQuality.toString(),
          isNumeric: true,
          hint: '0',
          onChanged: (val) {
            var value = int.tryParse(val) ?? 0;
            if (value < 0) {
              value = 0;
            } else if (value > 10) {
              value = 10;
            }
            s.updateDownloadOptions(opts.copyWith(audioQuality: value));
          },
        ),
      ),
      _SettingDef(
        title: locale.sRemuxVideo,
        description: locale.sRemuxVideoDesc,
        category: SettingCategory.video,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.disableRemuxVideo;
          return Row(
            children: [
              // 1. Switch maestro para encender/apagar la extracción
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(
                    disableRemuxVideo: !val,
                    // Si el usuario lo enciende y no había un navegador seleccionado,
                    // le asignamos Chrome como valor por defecto seguro.
                    remuxVideo: val && opts.remuxVideo == null
                        ? RemuxVideoFormat.mkv
                        : opts.remuxVideo,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 2. Dropdown de selección (Solo visible si el Switch está encendido)
              if (isEnabled)
                Expanded(
                  child: LazyDropdown<RemuxVideoFormat>(
                    // Muestra el valor guardado, o mkv por defecto
                    value: opts.remuxVideo ?? RemuxVideoFormat.mkv,
                    items: RemuxVideoFormat.values,
                    // Formateamos "mkv" a "MKV" visualmente
                    labelBuilder: (r) => r.name.toUpperCase(),
                    onChanged: (val) =>
                        s.updateDownloadOptions(opts.copyWith(remuxVideo: val)),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sEmbedSubs,
        description: locale.sEmbedSubsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.embedSubs,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(embedSubs: val)),
        ),
      ),
      _SettingDef(
        title: locale.sEmbedThumbnail,
        description: locale.sEmbedThumbnailDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.embedThumbnail,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(embedThumbnail: val)),
        ),
      ),
      _SettingDef(
        title: locale.sEmbedMetadata,
        description: locale.sEmbedMetadataDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.embedMetadata,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(embedMetadata: val)),
        ),
      ),
      _SettingDef(
        title: locale.sEmbedChapters,
        description: locale.sEmbedChaptersDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.embedChapters,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(embedChapters: val)),
        ),
      ),
      _SettingDef(
        title: locale.sEmbedInfoJson,
        description: locale.sEmbedInfoJsonDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.embedInfoJson,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(embedInfoJson: val)),
        ),
      ),
      _SettingDef(
        title: locale.sFormat,
        description: locale.sFormatDesc,
        category: SettingCategory.video,
        type: ControllerType.text,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.format,
          hint: 'bestvideo+bestaudio/best',
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(format: val.trim())),
        ),
      ),
      _SettingDef(
        title: locale.sXattrs,
        description: locale.sXattrsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.xattrs,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(xattrs: val)),
        ),
      ),
      _SettingDef(
        title: locale.sFixup,
        description: locale.sFixupDesc,
        category: SettingCategory.video,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<FixupOption>(
          value: opts.fixup,
          items: FixupOption.values,
          labelBuilder: (m) => m.name.toUpperCase(),
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(fixup: val)),
        ),
      ),
      _SettingDef(
        title: locale.sFFmpegLocation,
        description: locale.sFFmpegLocationDesc,
        category: SettingCategory.video,
        type: ControllerType.complex,
        controlBuilder: (c, s) => LazyTextField(
          value: opts.ffmpegLocation,
          hint: locale.sNotConfigured,
          readOnly: true,
          onChanged: (val) => {},
        ),
      ),
      _SettingDef(
        title: locale.sConvertThumbnails,
        description: locale.sConvertThumbnailsDesc,
        category: SettingCategory.video,
        type: ControllerType.dropdown,
        controlBuilder: (c, s) => LazyDropdown<ThumbnailFormat>(
          value: opts.convertThumbnails,
          items: ThumbnailFormat.values,
          labelBuilder: (m) => m.name.toUpperCase(),
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(convertThumbnails: val)),
        ),
      ),
      _SettingDef(
        title: locale.sWriteSubs,
        description: locale.sWriteSubsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.writeSubs,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(writeSubs: val)),
        ),
      ),
      _SettingDef(
        title: locale.sWriteAutoSubs,
        description: locale.sWriteAutoSubsDesc,
        category: SettingCategory.video,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.writeAutoSubs,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(writeAutoSubs: val)),
        ),
      ),
      // --- DOWNLOAD ---
      _SettingDef(
        title: locale.sOutput,
        description: locale.sOutputDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) => LazyList(
          value: opts.output,
          suggestions: const [
            "id",
            "title",
            "fulltitle",
            "ext",
            "alt_title",
            "description",
            "display_id",
            "uploader",
            "uploader_id",
            "uploader_url",
            "license",
            "creators",
            "creator",
            "timestamp",
            "upload_date",
            "release_timestamp",
            "release_date",
            "release_year",
            "modified_timestamp",
            "modified_date",
            "channel",
            "channel_id",
            "channel_url",
            "channel_follower_count",
            "channel_is_verified",
            "location",
            "duration",
            "duration_string",
            "view_count",
            "concurrent_view_count",
            "like_count",
            "dislike_count",
            "repost_count",
            "average_rating",
            "comment_count",
            "age_limit",
            "live_status",
            "is_live",
            "was_live",
            "playable_in_embed",
            "availability",
            "media_type",
            "start_time",
            "end_time",
            "extractor",
            "extractor_key",
            "epoch",
            "autonumber",
            "video_autonumber",
            "n_entries",
            "playlist_id",
            "playlist_title",
            "playlist",
            "playlist_count",
            "playlist_index",
            "playlist_autonumber",
            "playlist_uploader",
            "playlist_uploader_id",
            "playlist_channel",
            "playlist_channel_id",
            "playlist_webpage_url",
            "webpage_url",
            "webpage_url_basename",
            "webpage_url_domain",
            "original_url",
            "categories",
            "tags",
            "cast",
            "chapter",
            "chapter_number",
            "chapter_id",
            "series",
            "series_id",
            "season",
            "season_number",
            "season_id",
            "episode",
            "episode_number",
            "episode_id",
            "track",
            "track_number",
            "track_id",
            "artists",
            "artist",
            "genres",
            "genre",
            "composers",
            "composer",
            "album",
            "album_type",
            "album_artists",
            "album_artist",
            "disc_number",
            "section_title",
            "section_number",
            "section_start",
            "section_end",
          ],
          restrictToSuggestions: false,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(output: val)),
        ),
      ),
      _SettingDef(
        title: locale.sPaths,
        description: locale.sPathsDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Iteramos directamente sobre las 4 opciones posibles del Enum
            children: PathsKey.values.map((runtime) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: LazyTextField(
                  label: runtime.name.toUpperCase(),
                  hint: locale.sNotConfigured,
                  value: opts.paths[runtime] ?? '',
                  pickDirectory: true,
                  library: 'filesystem_picker',
                  onChanged: (val) {
                    final newMap = Map<PathsKey, String>.from(opts.paths);
                    if (val.trim().isEmpty) {
                      newMap.remove(runtime);
                    } else {
                      newMap[runtime] = val.trim();
                    }
                    s.updateDownloadOptions(opts.copyWith(paths: newMap));
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
      _SettingDef(
        title: locale.sDownloadArchive,
        description: locale.sDownloadArchiveDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.disableDownloadArchive;
          return Row(
            children: [
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(disableDownloadArchive: !val),
                ),
              ),
              const SizedBox(width: 16),
              if (isEnabled)
                Expanded(
                  child: LazyTextField(
                    value: opts.downloadArchive ?? '',
                    hint: locale.sSelectFile,
                    pickFile: true,
                    library: 'filesystem_picker',
                    onChanged: (val) => s.updateDownloadOptions(
                      opts.copyWith(downloadArchive: val.trim()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sConcurrentFragments,
        description: locale.sConcurrentFragmentsDesc,
        category: SettingCategory.download,
        type: ControllerType.text,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          return LazyTextField(
            value: opts.concurrentFragments.toString(),
            isNumeric: true,
            hint: '1',
            onChanged: (val) {
              final intValue = int.tryParse(val) ?? 1;

              final safeValue = intValue < 1 ? 1 : intValue;

              s.updateDownloadOptions(
                opts.copyWith(concurrentFragments: safeValue),
              );
            },
          );
        },
      ),
      _SettingDef(
        title: locale.sBreakOnExisting,
        description: locale.sBreakOnExistingDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.breakOnExisting,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(breakOnExisting: val)),
        ),
      ),
      _SettingDef(
        title: locale.sWindowsFilenames,
        description: locale.sWindowsFilenamesDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.windowsFilenames,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(windowsFilenames: val)),
        ),
      ),
      _SettingDef(
        title: locale.sAbortOnUnavailableFragments,
        description: locale.sAbortOnUnavailableFragmentsDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.abortOnUnavailableFragments,
          onChanged: (val) => s.updateDownloadOptions(
            opts.copyWith(abortOnUnavailableFragments: val),
          ),
        ),
      ),
      _SettingDef(
        title: locale.sKeepFragments,
        description: locale.sKeepFragmentsDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.keepFragments,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(keepFragments: val)),
        ),
      ),
      _SettingDef(
        title: locale.sForceOverwrites,
        description: locale.sForceOverwritesDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.forceOverwrites,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(forceOverwrites: val)),
        ),
      ),
      _SettingDef(
        title: locale.sWriteThumbnail,
        description: locale.sWriteThumbnailDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.writeThumbnail,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(writeThumbnail: val)),
        ),
      ),
      _SettingDef(
        title: locale.sLiveFromStart,
        description: locale.sLiveFromStartDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.liveFromStart,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(liveFromStart: val)),
        ),
      ),
      _SettingDef(
        title: locale.sWaitForVideo,
        description: locale.sWaitForVideoDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final isEnabled = !opts.disableWaitForVideo;
          return Row(
            children: [
              Switch(
                value: isEnabled,
                onChanged: (val) => s.updateDownloadOptions(
                  opts.copyWith(disableWaitForVideo: !val),
                ),
              ),
              const SizedBox(width: 16),
              if (isEnabled)
                Expanded(
                  child: LazyTextField(
                    value: opts.waitForVideo?.toString() ?? '',
                    isNumeric: true,
                    hint: '666',
                    onChanged: (val) => s.updateDownloadOptions(
                      opts.copyWith(waitForVideo: int.tryParse(val)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sMarkWatched,
        description: locale.sMarkWatchedDesc,
        category: SettingCategory.download,
        type: ControllerType.switchCtrl,
        controlBuilder: (c, s) => Switch(
          value: opts.markWatched,
          onChanged: (val) =>
              s.updateDownloadOptions(opts.copyWith(markWatched: val)),
        ),
      ),
      _SettingDef(
        title: locale.sJsRuntimes,
        description: locale.sJsRuntimesDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Iteramos directamente sobre las 4 opciones posibles del Enum
            children: JsRuntime.values.map((runtime) {
              final isLocked = runtime == JsRuntime.quickjs;
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: LazyTextField(
                  label: runtime.name.toUpperCase(),
                  hint: locale.sNotConfigured,
                  value: opts.jsRuntimes[runtime] ?? '',
                  readOnly: isLocked,
                  pickFile: !isLocked,
                  library: 'filesystem_picker',
                  onChanged: (val) {
                    if (isLocked) return;
                    final newMap = Map<JsRuntime, String>.from(opts.jsRuntimes);
                    if (val.trim().isEmpty) {
                      newMap.remove(runtime);
                    } else {
                      newMap[runtime] = val.trim();
                    }
                    s.updateDownloadOptions(opts.copyWith(jsRuntimes: newMap));
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
      _SettingDef(
        title: locale.sSkipPlaylistAfterErrors,
        description: locale.sSkipPlaylistAfterErrorsDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.infiniteSkipPlaylistAfterErrors;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(
                      infiniteSkipPlaylistAfterErrors: !val,
                      skipPlaylistAfterErrors: val
                          ? (opts.skipPlaylistAfterErrors ?? 3)
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.skipPlaylistAfterErrors?.toString() ?? '3',
                        isNumeric: true,
                        hint: '3',
                        onChanged: (val) {
                          final intValue = int.tryParse(val) ?? 1;
                          final safeValue = intValue < 1 ? 1 : intValue;
                          s.updateDownloadOptions(
                            opts.copyWith(skipPlaylistAfterErrors: safeValue),
                          );
                        },
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sRetries,
        description: locale.sRetriesDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.infiniteRetries;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(
                      infiniteRetries: !val,
                      retries: val ? (opts.retries ?? 3) : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.retries?.toString() ?? '3',
                        isNumeric: true,
                        hint: '3',
                        onChanged: (val) {
                          final intValue = int.tryParse(val) ?? 1;
                          final safeValue = intValue < 1 ? 1 : intValue;
                          s.updateDownloadOptions(
                            opts.copyWith(retries: safeValue),
                          );
                        },
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sFileAccessRetries,
        description: locale.sFileAccessRetriesDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.infiniteFileAccessRetries;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(
                      infiniteFileAccessRetries: !val,
                      fileAccessRetries: val
                          ? (opts.fileAccessRetries ?? 3)
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.fileAccessRetries?.toString() ?? '3',
                        isNumeric: true,
                        hint: '3',
                        onChanged: (val) {
                          final intValue = int.tryParse(val) ?? 1;
                          final safeValue = intValue < 1 ? 1 : intValue;
                          s.updateDownloadOptions(
                            opts.copyWith(fileAccessRetries: safeValue),
                          );
                        },
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sFragmentRetries,
        description: locale.sFragmentRetriesDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.infiniteFragmentRetries;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(
                      infiniteFragmentRetries: !val,
                      fragmentRetries: val ? (opts.fragmentRetries ?? 3) : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.fragmentRetries?.toString() ?? '3',
                        isNumeric: true,
                        hint: '3',
                        onChanged: (val) {
                          final intValue = int.tryParse(val) ?? 1;
                          final safeValue = intValue < 1 ? 1 : intValue;
                          s.updateDownloadOptions(
                            opts.copyWith(fragmentRetries: safeValue),
                          );
                        },
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sExtractorRetries,
        description: locale.sExtractorRetriesDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.infiniteExtractorRetries;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(
                      infiniteExtractorRetries: !val,
                      extractorRetries: val
                          ? (opts.extractorRetries ?? 3)
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.extractorRetries?.toString() ?? '3',
                        isNumeric: true,
                        hint: '3',
                        onChanged: (val) {
                          final intValue = int.tryParse(val) ?? 1;
                          final safeValue = intValue < 1 ? 1 : intValue;
                          s.updateDownloadOptions(
                            opts.copyWith(extractorRetries: safeValue),
                          );
                        },
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      _SettingDef(
        title: locale.sLimitRate,
        description: locale.sLimitRateDesc,
        category: SettingCategory.download,
        type: ControllerType.complex,
        controlBuilder: (c, s) {
          final opts = s.downloadOptions;
          final hasLimit = !opts.disableLimitRate;
          return Row(
            children: [
              Switch(
                value: hasLimit,
                onChanged: (val) {
                  s.updateDownloadOptions(
                    opts.copyWith(disableLimitRate: !val),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: hasLimit
                    ? LazyTextField(
                        value: opts.limitRate ?? '',
                        hint: '1MB',
                        pickFile: true,
                        onChanged: (val) => s.updateDownloadOptions(
                          opts.copyWith(limitRate: val.trim()),
                        ),
                      )
                    : Text(
                        locale.sUnlimited,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ];
  }

  // ===========================================================================
  // CONSTRUCCIÓN DE LA UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SettingsController>();
    final locale = context.watch<LocaleController>().localeStrings;
    final allSettings = _getAllSettings(ctrl, locale);

    return Scaffold(
      appBar: _buildAppBar(locale),
      body: _isSearching
          ? _buildSearchResults(allSettings, locale)
          : LayoutBuilder(
              builder: (context, constraints) {
                // Si el ancho es muy pequeño, cambiamos al layout vertical
                final isShort = constraints.maxWidth < 600;
                if (isShort) return _buildVerticalLayout(allSettings, locale);
                return _buildHorizontalLayout(allSettings, locale);
              },
            ),
    );
  }

  // --- BARRA SUPERIOR ---
  PreferredSizeWidget _buildAppBar(AppStringKey locale) {
    if (_isSearching) {
      return AppBar(
        title: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          autofocus: true,
          decoration: InputDecoration(
            hintText: locale.sSearchConfig,
            border: InputBorder.none,
          ),
          onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              if (_searchQuery.isEmpty) {
                setState(() => _isSearching = false);
              } else {
                _searchCtrl.clear();
                setState(() => _searchQuery = '');
              }
            },
          ),
        ],
        // Oculta la flecha atrás nativa
        automaticallyImplyLeading: false,
      );
    }

    return AppBar(
      title: Text(locale.sTitle),
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          onPressed: () =>
              TutorialUtils.showSettingsTutorial(context, force: true),
        ),
        IconButton(
          key: AppTutorialKeys.settingsSearch,
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _isSearching = true),
        ),
      ],
    );
  }

  // --- RESULTADOS DE BÚSQUEDA ---
  Widget _buildSearchResults(List<_SettingDef> settings, AppStringKey locale) {
    final results = settings
        .where((s) => s.title.toLowerCase().contains(_searchQuery))
        .toList();

    if (results.isEmpty) {
      return Center(child: Text(locale.sNoResults));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      separatorBuilder: (context, index) =>
          Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      itemBuilder: (context, index) {
        final setting = results[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              setting.category == SettingCategory.general
                  ? locale.sGeneral
                  : setting.category == SettingCategory.network
                  ? locale.sNetwork
                  : setting.category == SettingCategory.video
                  ? locale.sVideo
                  : locale.sDownload,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
            _buildRow(setting),
          ],
        );
      },
    );
  }

  // --- PANTALLA NORMAL (Pestañas horizontales, deslizable) ---
  Widget _buildVerticalLayout(List<_SettingDef> settings, AppStringKey locale) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            key: AppTutorialKeys.settingsTabs,
            tabs: [
              Tab(icon: Icon(Icons.settings), text: locale.sGeneral),
              Tab(icon: Icon(Icons.wifi), text: locale.sNetwork),
              Tab(icon: Icon(Icons.movie), text: locale.sVideo),
              Tab(icon: Icon(Icons.download), text: locale.sDownload),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCategoryList(settings, SettingCategory.general),
                _buildCategoryList(settings, SettingCategory.network),
                _buildCategoryList(settings, SettingCategory.video),
                _buildCategoryList(settings, SettingCategory.download),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- PANTALLA BAJA (Iconos laterales) ---
  Widget _buildHorizontalLayout(
    List<_SettingDef> settings,
    AppStringKey locale,
  ) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) =>
              setState(() => _selectedIndex = index),
          labelType: NavigationRailLabelType.none,
          destinations: [
            NavigationRailDestination(
              icon: Padding(
                key: AppTutorialKeys.settingsTabs,
                padding: const EdgeInsets.all(4.0),
                child: const Icon(Icons.settings),
              ),
              label: Text(locale.sGeneral),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.wifi),
              label: Text(locale.sNetwork),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.movie),
              label: Text(locale.sVideo),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.download),
              label: Text(locale.sDownload),
            ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildCategoryList(settings, SettingCategory.general),
              _buildCategoryList(settings, SettingCategory.network),
              _buildCategoryList(settings, SettingCategory.video),
              _buildCategoryList(settings, SettingCategory.download),
            ],
          ),
        ),
      ],
    );
  }

  // --- CREADOR DE LISTAS DE CATEGORÍA ---
  Widget _buildCategoryList(
    List<_SettingDef> settings,
    SettingCategory category,
  ) {
    final catSettings = settings.where((s) => s.category == category).toList();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: catSettings.length,
      separatorBuilder: (context, index) =>
          Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      itemBuilder: (context, index) => _buildRow(catSettings[index]),
    );
  }

  // Transforma la definición abstracta en el Widget Visual final
  Widget _buildRow(_SettingDef setting) {
    return SettingRow(
      title: setting.title,
      description: setting.description,
      type: setting.type,
      child: setting.controlBuilder(
        context,
        context.read<SettingsController>(),
      ),
    );
  }
}
