# Vidra i18n structure

Localization now relies on JSONC assets so translators do not need to touch Dart
code:

- `lib/i18n/i18n.dart` defines every key (`AppStringKey`, `ErrorStringKey`),
	loads the JSONC assets into memory, exposes `resolveAppString`, and exports
	`VidraLocalizations`.
- `lib/i18n/delegates/vidra_localizations.dart` bridges Flutter's
	`LocalizationsDelegate` with the runtime loader.
- `i18n/locales/<lang>/ui.jsonc` and `errors.jsonc` contain per-language
	translations. Add new locales by dropping JSONC files in the corresponding
	folder and running `flutter pub run build_runner` is **not** required.

All JSON files may include comments or trailing commas because they are parsed
through the [`jsonc`](https://pub.dev/packages/jsonc) package.
