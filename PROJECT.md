# Project: Cut Video Floating Action Button & SponsorBlock Modal

## Architecture
Vidra is a Flutter/Python video download manager.
- **Frontend Layer (`lib/`)**:
  - `lib/features/locales/domain/locale.dart` & `i18n/*.jsonc`: Centralized string catalog with `AppStringKey` getters, registered in `_allAppStrings`.
  - `lib/features/settings/`: `SettingsController` holds `DownloadOptions` with `sponsorblockRemove` (`List<SponsorblockCategory>`), reactive via `ChangeNotifier`.
  - `lib/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart`: Modal bottom sheet containing `LazyList` bound to `opts.sponsorblockRemove`.
  - `lib/features/downloads/presentation/downloads_screen.dart`: FAB row hosting Cut Video FAB with dynamic badge ('1' when `sponsorblockRemove.isNotEmpty`), Quick Settings FAB, and Download Extended FAB.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | i18n Localization Keys | Add `d_cut_video`, `cv_title`, `cv_close` to `en.jsonc`, `es.jsonc`, and `locale.dart` (`AppStringKey` & `_allAppStrings`) | M1 | Survey & R3 |
| 2 | Cut Video Bottom Sheet | `CutVideoBottomSheet` with `ClipRRect`, drag handle, header (scissors icon, title, close), `LazyList` with `SponsorblockCategory.values` two-way bound to `SettingsController` | M1 | Survey & R2 |
| 3 | Cut Video FAB & Dynamic Badge | Position `FloatingActionButton` left of Quick Settings in `DownloadsScreen`, scissors icon, `d_cut_video` tooltip, unique hero tag `cut_video_fab`, dynamic red badge with '1' when `sponsorblockRemove.isNotEmpty` | M1 | Survey & R1 |
| 4 | E2E & Widget Test Suite | Comprehensive tests covering Tiers 1-4 for FAB presence, badge toggling, modal opening, category selection, two-way state binding, and i18n fallback | M2 | Survey & Verification Plan |
| 5 | Full Test Suite Pass & Adversarial Hardening | Pass 100% test suite, adversarial coverage stress-testing (Tier 5), forensic integrity audit, zero `dart analyze` issues | M3 | Verification Plan & Final Milestone |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Cut Video Feature Implementation | `i18n/en.jsonc`, `i18n/es.jsonc`, `lib/features/locales/domain/locale.dart`, `lib/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart`, `lib/features/downloads/presentation/downloads_screen.dart` | none | DONE |
| 2 | E2E Testing Track | `test/features/downloads/presentation/cut_video_bottom_sheet_test.dart`, `test/features/downloads/presentation/cut_video_fab_test.dart`, updates to existing tests, publish `TEST_READY.md` | M1 | DONE |
| 3 | Final Milestone & Adversarial Hardening | Pass 100% E2E tests, Tier 5 adversarial hardening, forensic integrity audit, `dart analyze` & `flutter test` verification | M1, M2 | DONE |

## Interface Contracts
### `AppStringKey` (Locales) ↔ UI Components
- `locale.dCutVideo`: Localized string for Cut Video button tooltip.
- `locale.cvTitle`: Localized string for Cut Video modal title.
- `locale.cvClose`: Localized string for Cut Video modal close button tooltip.
- `locale.cvDescription`: Localized string for modal category removal description.

### `CutVideoBottomSheet` ↔ `SettingsController`
- `CutVideoBottomSheet.show(BuildContext context)`: Invokes modal with `showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, constraints: BoxConstraints(maxWidth: 640), builder: ...)`.
- Two-way binding: Reads `settingsCtrl.downloadOptions.sponsorblockRemove`, updates via `settingsCtrl.updateDownloadOptions(opts.copyWith(sponsorblockRemove: newEnums))`.

### `DownloadsScreen` ↔ `SettingsController`
- Watches `SettingsController` via `context.watch<SettingsController>()`.
- Renders `Badge(isLabelVisible: opts.sponsorblockRemove.isNotEmpty, backgroundColor: Colors.red, label: const Text('1'), child: FloatingActionButton(heroTag: 'cut_video_fab', tooltip: locale.dCutVideo, onPressed: () => CutVideoBottomSheet.show(context), child: const Icon(Icons.cut_outlined)))`.

## Code Layout
- `i18n/en.jsonc`, `i18n/es.jsonc`: English and Spanish localization dictionaries.
- `lib/features/locales/domain/locale.dart`: `AppStringKey` getters and `_allAppStrings` registry.
- `lib/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart`: Cut Video bottom sheet modal widget.
- `lib/features/downloads/presentation/downloads_screen.dart`: Downloads screen with FAB row.
- `test/features/downloads/presentation/cut_video_bottom_sheet_test.dart`: Bottom sheet widget tests.
- `test/features/downloads/presentation/cut_video_fab_test.dart`: Cut Video FAB & badge widget tests.
- `test/features/downloads/presentation/cut_video_bottom_sheet_stress_test.dart`: Bottom sheet stress tests.
- `test/features/downloads/presentation/downloads_screen_stress_test.dart`: Downloads screen layout & badge stress tests.
- `test/features/downloads/presentation/downloads_screen_fab_test.dart`: Updated FAB row tests.
