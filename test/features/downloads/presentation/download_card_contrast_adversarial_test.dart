import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/shared/widgets/download_card.dart';

/// Standard WCAG 2.1 relative luminance calculation
double calculateRelativeLuminance(Color color) {
  double channelLuminance(double channel) {
    if (channel <= 0.04045) {
      return channel / 12.92;
    } else {
      return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }
  }

  final r = channelLuminance(color.r);
  final g = channelLuminance(color.g);
  final b = channelLuminance(color.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Standard WCAG 2.1 contrast ratio calculation: (L1 + 0.05) / (L2 + 0.05)
double calculateContrastRatio(Color color1, Color color2) {
  final l1 = calculateRelativeLuminance(color1);
  final l2 = calculateRelativeLuminance(color2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'test_token';

  @override
  String? get serverLogsFilePath => '/path/to/logs';

  @override
  Future<void> get whenPortReady => Future.value();

  @override
  Future<void> stopBackendForUpdate() async {}

  @override
  Future<void> resumeInitialization() async {}

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class FakeDownloadRepository implements DownloadRepository {
  final List<String> actionsSent = [];

  @override
  Future<List<model.Download>> getAllDownloads() async => [];

  @override
  Future<model.Download?> getDownloadById(String id) async => null;

  @override
  Future<String> addDownload(String url, {Map<String, dynamic>? options}) async =>
      'mock_id';

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<List<model.SubDownload>> getEntries(String id) async => [];

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {}

  @override
  Future<void> pauseDownload(String id) async {
    actionsSent.add('pause:$id');
  }

  @override
  Future<void> resumeDownload(String id) async {
    actionsSent.add('resume:$id');
  }

  @override
  Future<void> cancelDownload(String id) async {
    actionsSent.add('cancel:$id');
  }

  @override
  Future<void> retryDownload(String id) async {
    actionsSent.add('retry:$id');
  }

  @override
  Future<void> deleteDownload(String id) async {
    actionsSent.add('delete:$id');
  }

  @override
  Future<String> fetchLogs(String? id) async => '';

  @override
  Stream<List<model.Delta>> watchGlobalProgress() => const Stream.empty();

  @override
  Stream<List<model.Delta>> watchDetailedProgress(String id) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;
  late FakeSystemController fakeSystemCtrl;
  late FakeDownloadRepository fakeRepo;
  late DownloadsController downloadsCtrl;

  setUp(() async {
    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
    fakeSystemCtrl = FakeSystemController();
    fakeRepo = FakeDownloadRepository();
    downloadsCtrl = DownloadsController(fakeRepo, fakeSystemCtrl);
  });

  Widget buildThemedApp({
    required Widget child,
    required ThemeData theme,
    Size size = const Size(800, 600),
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
      ],
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: textScaler,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('WCAG 2.1 Contrast Math Formula Verification', () {
    test('Black (#000000) vs White (#FFFFFF) produces exact 21.0:1 ratio', () {
      final ratio = calculateContrastRatio(
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, closeTo(21.0, 0.05));
    });

    test('Identical colors produce 1.0:1 ratio', () {
      final ratio = calculateContrastRatio(
        const Color(0xFF4F378B),
        const Color(0xFF4F378B),
      );
      expect(ratio, closeTo(1.0, 0.01));
    });
  });

  group('M2 Challenge: DownloadCard Error State Contrast & Opacity Elimination', () {
    testWidgets('Light Theme: Error card has NO Opacity dimming and maintains >= 4.5:1 text contrast on light card base', (tester) async {
      final info = model.Info(
        title: 'Light Theme Error Test Video',
        autor: 'Error Author',
        platform: 'YouTube',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=err1',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'HTTP 403 Forbidden Error',
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'err_light_1',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify NO Opacity widget is wrapping the card or its contents
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacityWidgets, isEmpty,
          reason: 'DownloadCard must NEVER use Opacity(0.6) dimming on error state');

      // 2. Verify Card border is error color (#B91C1C) with width 1.5
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);
      final cardWidget = tester.widget<Card>(cardFinder);
      final shape = cardWidget.shape as RoundedRectangleBorder;
      expect(shape.side.color, const Color(0xFFB91C1C),
          reason: 'Error border in light theme must use deep red #B91C1C');
      expect(shape.side.width, 1.5,
          reason: 'Error border width must be 1.5px');

      // 3. Verify Card Background vs Error Text Contrast on light card base
      final cardBgColor = cardWidget.color ?? theme.colorScheme.surfaceContainerHigh;
      final errorColor = shape.side.color;
      final errorContrastRatio = calculateContrastRatio(cardBgColor, errorColor);
      expect(errorContrastRatio, greaterThanOrEqualTo(4.5),
          reason: 'Error message/border contrast in Light Theme must be >= 4.5:1 (Got $errorContrastRatio:1)');

      // 4. Verify Title Text and Subtitle Text contrast on error card
      final titleColor = theme.colorScheme.onSurface;
      final titleContrast = calculateContrastRatio(cardBgColor, titleColor);
      expect(titleContrast, greaterThanOrEqualTo(4.5),
          reason: 'Title text contrast on error card in Light Theme must be >= 4.5:1 (Got $titleContrast:1)');

      final subtitleColor = theme.colorScheme.onSurfaceVariant;
      final subtitleContrast = calculateContrastRatio(cardBgColor, subtitleColor);
      expect(subtitleContrast, greaterThanOrEqualTo(4.5),
          reason: 'Subtitle text contrast on error card in Light Theme must be >= 4.5:1 (Got $subtitleContrast:1)');
    });

    testWidgets('Dark Theme: Error card has NO Opacity dimming and text maintains >= 4.5:1 AAA/AA contrast', (tester) async {
      final info = model.Info(
        title: 'Dark Theme Error Test Video',
        autor: 'Error Author',
        platform: 'YouTube',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=err2',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network Connection Timeout',
      );

      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'err_dark_1',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Opacity), findsNothing);

      final cardWidget = tester.widget<Card>(find.byType(Card));
      final shape = cardWidget.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.error);
      expect(shape.side.width, 1.5);

      final cardBgColor = cardWidget.color ?? theme.colorScheme.surfaceContainerHigh;

      // Text tokens contrast on dark card base
      final titleContrast = calculateContrastRatio(cardBgColor, theme.colorScheme.onSurface);
      expect(titleContrast, greaterThanOrEqualTo(4.5),
          reason: 'Title text contrast in Dark Theme must be >= 4.5:1 (Got $titleContrast:1)');

      final subtitleContrast = calculateContrastRatio(cardBgColor, theme.colorScheme.onSurfaceVariant);
      expect(subtitleContrast, greaterThanOrEqualTo(4.5),
          reason: 'Subtitle text contrast in Dark Theme must be >= 4.5:1 (Got $subtitleContrast:1)');

      // Component border meets WCAG 2.1 SC 1.4.11 non-text contrast requirement (>= 3.0:1)
      final borderContrast = calculateContrastRatio(cardBgColor, shape.side.color);
      expect(borderContrast, greaterThanOrEqualTo(3.0),
          reason: 'Error border contrast in Dark Theme must be >= 3.0:1 (Got $borderContrast:1)');
    });

    testWidgets('OLED Theme: Error card has NO Opacity dimming and maintains >= 4.5:1 contrast', (tester) async {
      final info = model.Info(
        title: 'OLED Theme Error Test Video',
        autor: 'Error Author',
        platform: 'YouTube',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=err3',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Backend Extraction Failure',
      );

      final theme = AppTheme.oledTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'err_oled_1',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Opacity), findsNothing);

      final cardWidget = tester.widget<Card>(find.byType(Card));
      final shape = cardWidget.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.error);
      expect(shape.side.width, 1.5);

      final cardBgColor = cardWidget.color ?? theme.colorScheme.surfaceContainerHigh;
      final errorContrast = calculateContrastRatio(cardBgColor, shape.side.color);
      expect(errorContrast, greaterThanOrEqualTo(4.5),
          reason: 'Error contrast in OLED Theme must be >= 4.5:1 (Got $errorContrast:1)');

      final titleContrast = calculateContrastRatio(cardBgColor, theme.colorScheme.onSurface);
      expect(titleContrast, greaterThanOrEqualTo(4.5));
    });
  });

  group('M2 Challenge: SlidableAction Foreground/Background Contrast in Light & Dark Modes', () {
    testWidgets('Light Mode: Warning (Folder/Pause) SlidableAction uses #D97706 with white foreground and tooltip', (tester) async {
      final info = model.Info(
        title: 'Light Slidable Warning Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=warn1',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.5,
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_warn_light',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag to open Slidable action pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Find pause CustomSlidableAction
      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final pauseAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFFD97706));

      expect(pauseAction.backgroundColor, const Color(0xFFD97706),
          reason: 'Warning action in Light theme must use amber #D97706');
      expect(pauseAction.foregroundColor, Colors.white,
          reason: 'Warning action in Light theme must use white foreground');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final pauseTooltip = tooltips.firstWhere((t) => t.message == 'Pausar' || t.message == 'Pause');
      expect(pauseTooltip.message, isNotEmpty,
          reason: 'Warning action must have a localized hover tooltip');
    });

    testWidgets('Dark Mode: Warning (Folder/Pause) SlidableAction uses #D97706 with white foreground and tooltip', (tester) async {
      final info = model.Info(
        title: 'Dark Slidable Warning Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=warn2',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.5,
      );

      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_warn_dark',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final pauseAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFFD97706));

      expect(pauseAction.backgroundColor, const Color(0xFFD97706),
          reason: 'Warning action in Dark theme must use amber #D97706');
      expect(pauseAction.foregroundColor, Colors.white,
          reason: 'Warning action in Dark theme must use white foreground');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final pauseTooltip = tooltips.firstWhere((t) => t.message == 'Pausar' || t.message == 'Pause');
      expect(pauseTooltip.message, isNotEmpty,
          reason: 'Warning action must have a localized hover tooltip');
    });

    testWidgets('Light Mode: Success (Resume) SlidableAction uses #10B981 with white foreground and tooltip', (tester) async {
      final info = model.Info(
        title: 'Light Slidable Success Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=succ1',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.paused,
        progressValue: 0.3,
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_succ_light',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final resumeAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFF10B981));

      expect(resumeAction.backgroundColor, const Color(0xFF10B981),
          reason: 'Success action in Light theme must use emerald #10B981');
      expect(resumeAction.foregroundColor, Colors.white,
          reason: 'Success action in Light theme must use white foreground');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final resumeTooltip = tooltips.firstWhere((t) => t.message == 'Reanudar' || t.message == 'Resume');
      expect(resumeTooltip.message, isNotEmpty,
          reason: 'Success action must have a localized hover tooltip');
    });

    testWidgets('Dark Mode: Success (Resume) SlidableAction uses #10B981 with white foreground and tooltip', (tester) async {
      final info = model.Info(
        title: 'Dark Slidable Success Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=succ2',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.paused,
        progressValue: 0.3,
      );

      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_succ_dark',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final resumeAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFF10B981));

      expect(resumeAction.backgroundColor, const Color(0xFF10B981),
          reason: 'Success action in Dark theme must use emerald #10B981');
      expect(resumeAction.foregroundColor, Colors.white,
          reason: 'Success action in Dark theme must use white foreground');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final resumeTooltip = tooltips.firstWhere((t) => t.message == 'Reanudar' || t.message == 'Resume');
      expect(resumeTooltip.message, isNotEmpty,
          reason: 'Success action must have a localized hover tooltip');
    });

    testWidgets('Light Mode: Delete SlidableAction has >= 4.5:1 AA contrast with #DC2626 and localized tooltip', (tester) async {
      final info = model.Info(
        title: 'Light Slidable Delete Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=del1',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_del_light',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final deleteAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFFDC2626));

      // Verify Delete action colors in Light Mode
      expect(deleteAction.backgroundColor, const Color(0xFFDC2626),
          reason: 'Delete action container must use solid red #DC2626');
      expect(deleteAction.foregroundColor, Colors.white,
          reason: 'Delete action foreground must use white');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final deleteTooltip = tooltips.firstWhere((t) => t.message == 'Eliminar' || t.message == 'Delete');
      expect(deleteTooltip.message, isNotEmpty,
          reason: 'Delete action must have a localized hover tooltip');

      final deleteRatio = calculateContrastRatio(deleteAction.backgroundColor, deleteAction.foregroundColor!);
      expect(deleteRatio, greaterThanOrEqualTo(4.5),
          reason: 'Light mode Delete action contrast must meet WCAG AA (>= 4.5:1, Got $deleteRatio:1)');
    });

    testWidgets('Dark Mode: Delete SlidableAction has >= 4.5:1 AA contrast with #DC2626 and localized tooltip', (tester) async {
      final info = model.Info(
        title: 'Dark Slidable Delete Test',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=del2',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'slidable_del_dark',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final slidableActions = tester.widgetList<CustomSlidableAction>(find.byType(CustomSlidableAction)).toList();
      final deleteAction = slidableActions.firstWhere((a) => a.backgroundColor == const Color(0xFFDC2626));

      expect(deleteAction.backgroundColor, const Color(0xFFDC2626),
          reason: 'Delete action container must use solid red #DC2626');
      expect(deleteAction.foregroundColor, Colors.white,
          reason: 'Delete action foreground must use white');

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final deleteTooltip = tooltips.firstWhere((t) => t.message == 'Eliminar' || t.message == 'Delete');
      expect(deleteTooltip.message, isNotEmpty,
          reason: 'Delete action must have a localized hover tooltip');

      final deleteRatio = calculateContrastRatio(deleteAction.backgroundColor, deleteAction.foregroundColor!);
      expect(deleteRatio, greaterThanOrEqualTo(4.5),
          reason: 'Dark mode Delete action contrast must meet WCAG AA (>= 4.5:1, Got $deleteRatio:1)');
    });
  });

  group('M2 Challenge: Delete Button in Cancel Dialog & Light Theme Verification', () {
    testWidgets('Light Theme: Cancel Dialog FilledButton uses #B91C1C background and white text (>= 4.5:1)', (tester) async {
      final info = model.Info(
        title: 'Cancel Dialog Test Video',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=cancel_dialog',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.4,
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'cancel_dialog_test',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Slidable pane and tap cancel action
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.byType(AlertDialog), findsOneWidget);
      final filledBtnFinder = find.byType(FilledButton);
      expect(filledBtnFinder, findsOneWidget);

      final filledButton = tester.widget<FilledButton>(filledBtnFinder);
      final btnStyle = filledButton.style!;
      final bg = btnStyle.backgroundColor?.resolve({});
      final fg = btnStyle.foregroundColor?.resolve({});

      expect(bg, const Color(0xFFB91C1C),
          reason: 'Cancel dialog confirm button in Light mode must use deep red #B91C1C');
      expect(fg, Colors.white,
          reason: 'Cancel dialog confirm button text must be white');

      final ratio = calculateContrastRatio(bg!, fg!);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Cancel dialog button contrast must be >= 4.5:1 (Got $ratio:1)');
    });
  });

  group('M2 Challenge: Telemetry Dynamic Typography & Tabular Numbers', () {
    testWidgets('Light Theme: Progress label and Speed telemetry adapt with high contrast and tabular figures', (tester) async {
      final info = model.Info(
        title: 'Telemetry Test Video',
        autor: 'Author X',
        platform: 'Twitch',
        type: model.DownloadType.video,
        url: 'https://twitch.tv/videos/123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.65,
        progressLabel: '65.0% of 1.2 GB',
        speed: '14.8 MB/s',
      );

      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'telemetry_light',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify progress label text
      final progressTextFinder = find.text('65.0% of 1.2 GB');
      expect(progressTextFinder, findsOneWidget);
      final progressTextWidget = tester.widget<Text>(progressTextFinder);
      expect(progressTextWidget.style?.fontFeatures, contains(const FontFeature.tabularFigures()),
          reason: 'Progress label must include FontFeature.tabularFigures()');

      // Verify speed text
      final speedTextFinder = find.text('14.8 MB/s');
      expect(speedTextFinder, findsOneWidget);
      final speedTextWidget = tester.widget<Text>(speedTextFinder);
      expect(speedTextWidget.style?.fontFeatures, contains(const FontFeature.tabularFigures()),
          reason: 'Speed telemetry must include FontFeature.tabularFigures()');

      // Contrast checks on Light Card Background
      final cardBgColor = theme.colorScheme.surfaceContainerHigh;
      final speedColor = speedTextWidget.style?.color ?? theme.colorScheme.primary;
      final progressColor = progressTextWidget.style?.color ?? theme.colorScheme.onSurfaceVariant;

      final speedContrast = calculateContrastRatio(cardBgColor, speedColor);
      expect(speedContrast, greaterThanOrEqualTo(4.5),
          reason: 'Speed telemetry contrast in Light mode must be >= 4.5:1 (Got $speedContrast:1)');

      final progressContrast = calculateContrastRatio(cardBgColor, progressColor);
      expect(progressContrast, greaterThanOrEqualTo(4.5),
          reason: 'Progress label contrast in Light mode must be >= 4.5:1 (Got $progressContrast:1)');
    });

    testWidgets('Dark Theme: Telemetry tokens adapt dynamically with high contrast', (tester) async {
      final info = model.Info(
        title: 'Telemetry Dark Test Video',
        autor: 'Author Y',
        platform: 'YouTube',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=dark_tel',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.88,
        progressLabel: '88.0%',
        speed: '32.1 MB/s',
      );

      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        buildThemedApp(
          theme: theme,
          child: DownloadCard(
            downloadId: 'telemetry_dark',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final speedTextFinder = find.text('32.1 MB/s');
      expect(speedTextFinder, findsOneWidget);
      final speedTextWidget = tester.widget<Text>(speedTextFinder);
      expect(speedTextWidget.style?.fontFeatures, contains(const FontFeature.tabularFigures()));

      final cardBgColor = theme.colorScheme.surfaceContainerHigh;
      final speedColor = speedTextWidget.style?.color ?? theme.colorScheme.primary;
      final speedContrast = calculateContrastRatio(cardBgColor, speedColor);
      expect(speedContrast, greaterThanOrEqualTo(4.5),
          reason: 'Speed telemetry contrast in Dark mode must be >= 4.5:1 (Got $speedContrast:1)');
    });
  });

  group('M2 Challenge: Narrow Viewport (320dp) & 2.0x Dynamic Text Scaling Resilience', () {
    testWidgets('320dp viewport with 2.0x Text Scaling renders DownloadCard without RenderFlex overflow', (tester) async {
      final info = model.Info(
        title: 'Extremely Long Video Title That Might Cause RenderFlex Overflow On Tiny Screens',
        autor: 'Super Long Channel Name With Multiple Details',
        platform: 'YouTube Platform Long Name',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=long_name',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.45,
        progressLabel: '45.0% (1,450.2 MB / 3,200.0 MB)',
        speed: '128.5 MB/s',
      );

      await tester.pumpWidget(
        buildThemedApp(
          theme: AppTheme.lightTheme,
          size: const Size(320, 568),
          textScaler: const TextScaler.linear(2.0),
          child: DownloadCard(
            downloadId: 'narrow_scale_test',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'DownloadCard must not throw any RenderFlex overflow at 320dp width with 2.0x text scaling');
      expect(find.byType(DownloadCard), findsOneWidget);
    });
  });

  group('M2 Challenge: In-Progress Subtle Animated State Icon', () {
    testWidgets('In-Progress state uses TweenAnimationBuilder without blocking test execution', (tester) async {
      final info = model.Info(
        title: 'Animated Icon Test Video',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=anim_icon',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.5,
      );

      await tester.pumpWidget(
        buildThemedApp(
          theme: AppTheme.darkTheme,
          child: DownloadCard(
            downloadId: 'anim_icon_test',
            info: info,
            state: state,
            isDetailScreen: false,
          ),
        ),
      );
      // Pump initial frame
      await tester.pump();

      // Find the downloading icon inside TweenAnimationBuilder
      expect(find.byIcon(Icons.downloading), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsWidgets);

      // Verify pumpAndSettle safely terminates and does not hang in an infinite loop
      await tester.pumpAndSettle(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });
  });
}
