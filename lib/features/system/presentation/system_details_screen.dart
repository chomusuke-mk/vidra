import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/features/system/presentation/licenses_screen.dart';
import 'package:vidra/core/network/vidra_http_client.dart';

class SystemDetailsScreen extends StatelessWidget {
  const SystemDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Estado del Sistema',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 32),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildBackendStatus(context),
                const SizedBox(height: 24),

                const Text(
                  'Módulos y Actualizaciones',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _buildUpdateCard(
                  context,
                  ComponentType.app,
                  'Vidra App',
                  Icons.android,
                ),
                _buildUpdateCard(
                  context,
                  ComponentType.ytDlp,
                  'Motor yt-dlp',
                  Icons.terminal,
                ),
                _buildUpdateCard(
                  context,
                  ComponentType.ytDlpEjs,
                  'Parche EJS',
                  Icons.javascript,
                ),

                const SizedBox(height: 32),
                _buildAboutSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ZONA 1: ESTADO DEL BACKEND Y LOGS
  // ==========================================================================
  Widget _buildBackendStatus(BuildContext context) {
    final sysCtrl = context.watch<SystemController>();
    final isReady = sysCtrl.state == SystemState.ready;
    final hasError =
        sysCtrl.state == SystemState.missingResources ||
        sysCtrl.state == SystemState.fatalError;

    return Card(
      color: hasError ? Colors.red.withValues(alpha: 0.1) : null,
      child: ListTile(
        leading: Icon(
          isReady ? Icons.dns : Icons.dns_outlined,
          color: isReady
              ? Colors.green
              : (hasError ? Colors.red : Colors.orange),
        ),
        title: Text('Servidor Python: ${sysCtrl.state.name}'),
        subtitle: Text(
          isReady
              ? 'Puerto: ${sysCtrl.backendPort}'
              : 'Esperando disponibilidad...',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botón 1: Logs HTTP de la App (Solo si está Ready)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: !isReady
                  ? null
                  : () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            const Center(child: CircularProgressIndicator()),
                      );
                      try {
                        final client = context.read<VidraHttpClient>();
                        final logs = await client.getLogs();
                        if (context.mounted) {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (_) => _LogsDialog(logs: logs),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              child: const Text('App', style: TextStyle(fontSize: 12)),
            ),

            const SizedBox(width: 4),

            // Botón 2: Logs Nativos de Consola (SIEMPRE DISPONIBLE para debug)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: sysCtrl.serverLogsFilePath == null
                  ? null
                  : () async {
                      try {
                        final file = File(sysCtrl.serverLogsFilePath!);
                        if (await file.exists()) {
                          // Leemos los últimos 20000 caracteres para no ahogar la RAM si el archivo creció mucho
                          String rawLogs = await file.readAsString();
                          if (rawLogs.length > 20000) {
                            rawLogs =
                                "... (truncado) ...\n${rawLogs.substring(rawLogs.length - 20000)}";
                          }
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (_) => _LogsDialog(logs: rawLogs),
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'El archivo de log físico aún no existe.',
                                ),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al leer log físico: $e'),
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Server', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // ZONA 2: TARJETAS DE ACTUALIZACIÓN
  // ==========================================================================
  Widget _buildUpdateCard(
    BuildContext context,
    ComponentType type,
    String title,
    IconData icon,
  ) {
    final updateCtrl = context.watch<UpdateController>();
    final state = updateCtrl.getState(type);
    final isYtDlp = type == ComponentType.ytDlp;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Versión: ${state.version}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // Le pasamos el "title" para que el mensajito sepa cómo se llama el módulo
                _buildActionButton(context, type, state, updateCtrl, title),
              ],
            ),
            if (isYtDlp) ...[
              const Divider(height: 16),
              _buildChannelSelector(context, updateCtrl),
            ],
            if (state.status == ComponentStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: state.progress),
            ],
          ],
        ),
      ),
    );
  }

  // --- Lógica del Botón Dinámico ---
  Widget _buildActionButton(
    BuildContext context,
    ComponentType type,
    UpdateState state,
    UpdateController ctrl,
    String title,
  ) {
    switch (state.status) {
      // NUEVO ESTADO: Oculta el botón y muestra un indicador circular para evitar doble-taps.
      case ComponentStatus.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );

      case ComponentStatus.error:
        if (state.pendingUpdate != null) {
          return FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reintentar'),
            onPressed: () => ctrl.downloadAndInstall(type),
          );
        }
        return TextButton(
          onPressed: () => _handleCheckUpdate(context, ctrl, type, title),
          child: const Text('Buscar'),
        );

      case ComponentStatus.upToDate:
        return TextButton(
          onPressed: () => _handleCheckUpdate(context, ctrl, type, title),
          child: const Text('Buscar'),
        );

      case ComponentStatus.updateAvailable:
        final sysState = context.read<SystemController>().state;
        final isMissing =
            sysState == SystemState.missingResources &&
            type != ComponentType.app;

        return FilledButton.icon(
          style: isMissing
              ? FilledButton.styleFrom(backgroundColor: Colors.red)
              : null,
          icon: const Icon(Icons.download, size: 16),
          label: Text(isMissing ? 'Instalar Requerido' : 'Actualizar'),
          onPressed: () => ctrl.downloadAndInstall(type),
        );

      case ComponentStatus.downloading:
        return const Text(
          'Descargando...',
          style: TextStyle(color: Colors.blue),
        );
      case ComponentStatus.verifying:
        return const Text(
          'Validando PGP...',
          style: TextStyle(color: Colors.purple),
        );
      case ComponentStatus.installing:
        return const Text(
          'Instalando...',
          style: TextStyle(color: Colors.orange),
        );
    }
  }

  // --- Magia del Mensaje Final (SnackBar) ---
  Future<void> _handleCheckUpdate(
    BuildContext context,
    UpdateController ctrl,
    ComponentType type,
    String title,
  ) async {
    // Esto mostrará el spinner porque el controlador pondrá el estado en 'checking'
    final hasUpdate = await ctrl.checkForUpdates(
      manualCall: true,
      specificType: type,
    );

    // Si no encontró nada y el widget aún existe, lanzamos la notificación
    if (!hasUpdate && context.mounted) {
      final finalState = ctrl.getState(type).status;

      if (finalState == ComponentStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error de red al conectar con GitHub.'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('¡$title ya está en su última versión!')),
        );
      }
    }
  }

  Widget _buildChannelSelector(BuildContext context, UpdateController ctrl) {
    final prefs = context.watch<SharedPreferences>();
    final currentChannel = prefs.getString('channel_ytdlp') ?? 'stable';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Canal de actualización:', style: TextStyle(fontSize: 12)),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'stable',
              label: Text('Estable', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: 'nightly',
              label: Text('Nightly', style: TextStyle(fontSize: 11)),
            ),
          ],
          selected: {currentChannel},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> newSelection) async {
            prefs.setString('channel_ytdlp', newSelection.first);
            // Cuando cambias de canal, también hacemos el chequeo visual
            final hasUpdate = await ctrl.checkForUpdates(
              manualCall: true,
              specificType: ComponentType.ytDlp,
            );
            if (!hasUpdate && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No hay nuevas versiones en este canal.'),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // ZONA 3: ABOUT Y LICENCIAS
  // ==========================================================================
  Widget _buildAboutSection(BuildContext context) {
    return Column(
      children: [
        const CircleAvatar(
          radius: 36,
          backgroundImage: NetworkImage('https://github.com/chomusuke-mk.png'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Vidra App',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const Text(
          'Creado por Chomusuke',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 16),

        // Wrap alinea automáticamente todos los botones evitando desbordes (Overflows)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8, // Espacio horizontal
          runSpacing: 4, // Espacio vertical si hace salto de línea
          children: [
            TextButton.icon(
              icon: const Icon(Icons.favorite, color: Colors.red, size: 16),
              label: const Text('Patreon'),
              onPressed: () => launchUrl(
                Uri.parse('https://www.patreon.com/chomusuke_dev'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.coffee, color: Colors.orange, size: 16),
              label: const Text('Donar'),
              onPressed: () => launchUrl(
                Uri.parse('https://www.buymeacoffee.com/chomusuke'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.code, size: 16),
              label: const Text('GitHub'),
              onPressed: () => launchUrl(
                Uri.parse('https://github.com/chomusuke-mk/vidra'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.gavel, size: 16),
              label: const Text('Licencias'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LicensesScreen()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}

// ==========================================================================
// WIDGET ESTADO PARA LOGS (Soluciona el error del ScrollController)
// ==========================================================================
class _LogsDialog extends StatefulWidget {
  final String logs;
  const _LogsDialog({required this.logs});

  @override
  State<_LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<_LogsDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Logs Globales de Vidra'),
      content: SizedBox(
        width: double.maxFinite,
        child: Scrollbar(
          controller: _scrollController, // Vinculamos la barra...
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController, // ...con el contenido!
            child: SelectableText(
              widget.logs.isEmpty ? 'No hay logs aún.' : widget.logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
