import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';
import 'package:vidra/core/theme/layout.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart';

class DownloadActionButtons extends StatelessWidget {
  final String Function() getUrl;
  final VoidCallback? onDownloadSuccess;
  final bool isMainScreen;

  const DownloadActionButtons({
    super.key,
    required this.getUrl,
    this.onDownloadSuccess,
    this.isMainScreen = false,
  });

  void _addDownload(BuildContext context) async {
    final url = getUrl().trim();
    if (url.isEmpty) return;
    
    final settingsCtrl = context.read<SettingsController>();
    final downloadsCtrl = context.read<DownloadsController>();
    final currentOptions = settingsCtrl.getDownloadOptionsPayload();
    final locale = context.read<LocaleController>().localeStrings;
    
    final result = await downloadsCtrl.addDownload(
      url,
      currentOptions,
    );
    
    if (result) {
      onDownloadSuccess?.call();
      ToastUtils.showInfo(locale.dDownloadSent);
    } else {
      ToastUtils.showError(locale.dDownloadSentError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsCtrl = context.watch<SettingsController>();
    final locale = context.watch<LocaleController>().localeStrings;
    
    final activeModifiers = (settingsCtrl.downloadOptions.sponsorblockRemove.isNotEmpty ? 1 : 0) +
        (settingsCtrl.downloadOptions.cutVideo ? 1 : 0);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: activeModifiers > 0,
              backgroundColor: Colors.red,
              label: Text('$activeModifiers'),
              child: FloatingActionButton(
                key: isMainScreen ? AppTutorialKeys.mainCut : null,
                heroTag: isMainScreen ? 'cut_video_fab' : 'cut_video_fab_webview',
                tooltip: locale.dCutVideo,
                onPressed: () => CutVideoBottomSheet.show(context),
                child: const Icon(Icons.cut_outlined),
              ),
            ),
            const SizedBox(width: AppSpacing.space12),
            FloatingActionButton(
              key: isMainScreen ? AppTutorialKeys.mainQuickSettings : null,
              heroTag: isMainScreen ? 'quick_settings_fab' : 'quick_settings_fab_webview',
              tooltip: locale.dQuickSettings,
              onPressed: () => QuickSettingsBottomSheet.show(context),
              child: const Icon(Icons.construction_outlined),
            ),
            const SizedBox(width: AppSpacing.space12),
            FloatingActionButton.extended(
              heroTag: isMainScreen ? 'download_fab' : 'download_fab_webview',
              onPressed: () => _addDownload(context),
              icon: const Icon(Icons.download),
              label: Text(
                locale.dDownload,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
