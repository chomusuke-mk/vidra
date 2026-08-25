# E2E Test Infra: Cut Video FAB & Modal

## Test Philosophy
- Opaque-box, requirement-driven testing validating user-visible behavior and system state.
- Category-Partition + Boundary Value Analysis + Pairwise Combinatorial + Real-World Workload Testing.

## Feature Inventory
| # | Feature | Source | Tier 1 | Tier 2 | Tier 3 |
|---|---------|--------|:------:|:------:|:------:|
| 1 | Cut Video FAB Rendering & Tooltip | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | Dynamic Badge ('1' on non-empty, hidden on empty) | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | Modal Presentation & Styling (CutVideoBottomSheet) | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 4 | SponsorBlock Category Selection & Controller Binding | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 5 | i18n Key Resolution & Locale Switching | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |

## Test Architecture
- Test Runner: `flutter test <path_to_test>`
- Static Analysis: `dart analyze`
- Harness: `createTestApp` with `MockLocaleRepository`, `ChangeNotifierProvider<SettingsController>`, and fake repositories.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Cold app launch -> Empty badge -> Open Cut Video modal -> Select 'sponsor' category -> Close modal -> Verify red '1' badge appears on FAB | F1, F2, F3, F4 | Medium |
| 2 | Active categories -> Open Cut Video modal -> Remove all categories -> Close modal -> Verify badge disappears | F2, F3, F4 | Medium |
| 3 | Switch locale between 'en' and 'es' -> Verify tooltips, modal headers, and labels change accordingly | F1, F3, F5 | Medium |
| 4 | Multi-category selection (e.g. intro, outro, sponsor, selfpromo) -> Verify list serialization and persistence | F2, F4 | Medium |
| 5 | Viewport resizing (320px, 360px, 600px) with all 3 FABs active -> Verify no RenderFlex overflow and correct hit testing | F1, F2, F3 | High |

## Coverage Thresholds
- Tier 1 (Feature Coverage): >= 25 test cases across 5 features
- Tier 2 (Boundary & Corner Cases): >= 25 test cases
- Tier 3 (Cross-Feature Combinations): >= 5 test cases
- Tier 4 (Real-World Application Scenarios): >= 5 test cases
