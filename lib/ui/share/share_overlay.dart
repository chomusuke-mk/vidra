import 'package:flutter/material.dart';
import 'package:vidra/share/share_intent_payload.dart';
import 'package:vidra/share/share_preset_ids.dart';

typedef ShareQuickActionCallback = Future<bool> Function(String actionId);
typedef ShareManualActionCallback = Future<void> Function();

class ShareIntentOverlay extends StatefulWidget {
  const ShareIntentOverlay({
    super.key,
    required this.payload,
    required this.onQuickAction,
    required this.onManualAction,
  });

  final ShareIntentPayload payload;
  final ShareQuickActionCallback onQuickAction;
  final ShareManualActionCallback onManualAction;

  static Future<void> show({
    required BuildContext context,
    required ShareIntentPayload payload,
    required ShareQuickActionCallback onQuickAction,
    required ShareManualActionCallback onManualAction,
  }) {
    return Navigator.of(context).push(
      _ShareOverlayRoute(
        payload: payload,
        onQuickAction: onQuickAction,
        onManualAction: onManualAction,
      ),
    );
  }

  @override
  State<ShareIntentOverlay> createState() => _ShareIntentOverlayState();
}

class _ShareIntentOverlayState extends State<ShareIntentOverlay> {
  String? _runningActionId;
  bool _manualInProgress = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildSheet(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(ThemeData theme) {
    final urlsPreview = widget.payload.urls.take(3).toList(growable: false);
    final subtitle = widget.payload.displayName ?? widget.payload.subject;

    return GestureDetector(
      onTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compartir con Vidra',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (urlsPreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                urlsPreview.join('\n'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'RobotoMono',
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in _quickActions) _buildActionButton(action),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _manualInProgress ? null : _handleManualAction,
              icon: _manualInProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune),
              label: const Text('Otras descargas'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(_ShareQuickActionDescriptor action) {
    final isBusy = _runningActionId == action.id;
    return SizedBox(
      width: 220,
      child: FilledButton.tonal(
        onPressed: isBusy ? null : () => _handleQuickAction(action.id),
        style: FilledButton.styleFrom(alignment: Alignment.centerLeft),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (isBusy)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              Icon(action.icon),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(action.subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleQuickAction(String actionId) async {
    setState(() {
      _runningActionId = actionId;
    });
    final success = await widget.onQuickAction(actionId);
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _runningActionId = null;
      });
    }
  }

  Future<void> _handleManualAction() async {
    setState(() {
      _manualInProgress = true;
    });
    await widget.onManualAction();
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }
}

class _ShareOverlayRoute extends PageRoute<void> {
  _ShareOverlayRoute({
    required this.payload,
    required this.onQuickAction,
    required this.onManualAction,
  });

  final ShareIntentPayload payload;
  final ShareQuickActionCallback onQuickAction;
  final ShareManualActionCallback onManualAction;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Color get barrierColor => Colors.black54;

  @override
  String get barrierLabel => 'share_overlay';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: ShareIntentOverlay(
        payload: payload,
        onQuickAction: onQuickAction,
        onManualAction: onManualAction,
      ),
    );
  }
}

class _ShareQuickActionDescriptor {
  const _ShareQuickActionDescriptor({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

const List<_ShareQuickActionDescriptor> _quickActions = [
  _ShareQuickActionDescriptor(
    id: SharePresetIds.videoBest,
    title: 'Descargar video best',
    subtitle: 'Máxima calidad disponible',
    icon: Icons.movie_outlined,
  ),
  _ShareQuickActionDescriptor(
    id: SharePresetIds.audioBest,
    title: 'Descargar audio best',
    subtitle: 'Extrae la mejor pista',
    icon: Icons.graphic_eq,
  ),
];
