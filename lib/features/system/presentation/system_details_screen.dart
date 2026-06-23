import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'licenses_screen.dart';

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
          // Handle para arrastrar el BottomSheet
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
        trailing: OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long, size: 16),
          label: const Text('Logs'),
          onPressed: () {
            // TODO: Llamar a vidraHttpClient.getLogs() y mostrarlos en un dialog
          },
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
                // --- BOTÓN PRINCIPAL REACTIVO ---
                _buildActionButton(context, type, state, updateCtrl),
              ],
            ),

            // Selector de canal (Stable / Nightly) solo para yt-dlp
            if (isYtDlp) ...[
              const Divider(height: 16),
              _buildChannelSelector(context, updateCtrl),
            ],

            // Barra de progreso si está descargando
            if (state.status == ComponentStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: state.progress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    ComponentType type,
    UpdateState state,
    UpdateController ctrl,
  ) {
    switch (state.status) {
      case ComponentStatus.upToDate:
      case ComponentStatus.error:
        return TextButton(
          onPressed: () => ctrl.checkForUpdates(manualCall: true),
          child: const Text('Buscar'),
        );
      case ComponentStatus.updateAvailable:
        // Si falta el recurso, resaltamos el botón para guiar al usuario
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
        return const Text('Descargando...');
      case ComponentStatus.verifying:
        return const Text('Validando PGP...');
      case ComponentStatus.installing:
        return const Text('Instalando...');
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
          onSelectionChanged: (Set<String> newSelection) {
            prefs.setString('channel_ytdlp', newSelection.first);
            ctrl.checkForUpdates(manualCall: true); // Re-evaluar
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
        const Text('Vidra App', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'Creado por Chomusuke',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.favorite, color: Colors.red, size: 16),
              label: const Text('Patreon'),
              onPressed: () {
                // TODO: url_launcher para abrir patreon
              },
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
        const SizedBox(height: 32),
      ],
    );
  }
}
