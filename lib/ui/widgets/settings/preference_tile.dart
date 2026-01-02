import 'package:flutter/material.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';
import 'package:vidra/models/preference.dart';

const double breakSize = 650;

class PreferenceTile extends StatelessWidget {
  const PreferenceTile({
    super.key,
    required this.preference,
    required this.languageValue,
    required this.control,
  });

  final Preference preference;
  final String languageValue;
  final PreferenceControl control;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = preference.description.get(
      languageValue,
      fallbackLocale: I18n.fallbackLocale,
    );
    final title = preference.name.get(
      languageValue,
      fallbackLocale: I18n.fallbackLocale,
    );

    Widget buildBody(bool forceStack) {
      final textColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
        ],
      );

      final headerChildren = <Widget>[Expanded(child: textColumn)];
      Widget? trailingBelow;

      if (control.headerTrailing != null) {
        if (forceStack) {
          trailingBelow = Align(
            alignment: Alignment.centerLeft,
            child: control.headerTrailing!,
          );
        } else {
          headerChildren.addAll([
            const SizedBox(width: 12),
            control.headerTrailing!,
          ]);
        }
      }

      final bool inlineControl = control.inline && !forceStack;

      if (inlineControl) {
        headerChildren.addAll([
          const SizedBox(width: 16),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerRight,
              child: control.control,
            ),
          ),
        ]);
      }

      final headerRow = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: headerChildren,
      );

      if (inlineControl) {
        return headerRow;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          headerRow,
          if (trailingBelow != null) ...[
            const SizedBox(height: 12),
            trailingBelow,
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: control.fullLine
                ? control.control
                : Align(
                    alignment: forceStack
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: control.control,
                  ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool forceStack = constraints.maxWidth < breakSize;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('tile_${preference.key}'),
              borderRadius: BorderRadius.circular(12),
              onTap: control.onTap == null ? null : () => control.onTap?.call(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: buildBody(forceStack),
              ),
            ),
          ),
        );
      },
    );
  }
}
