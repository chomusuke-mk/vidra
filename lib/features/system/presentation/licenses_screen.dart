import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

class LicenseItem {
  final String title;
  final String assetPath;

  LicenseItem(this.title, this.assetPath);
}

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  List<LicenseItem> _licenses = [];
  bool _isLoading = true;
  LicenseItem? _selectedLicense;

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    try {
      // Leemos el manifiesto de la app para descubrir los archivos dinámicamente
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();

      final List<LicenseItem> items = [];

      // 1. Agregamos las licencias principales primero
      if (allAssets.contains('LICENSE')) {
        items.add(LicenseItem('Vidra License', 'LICENSE'));
      }
      if (allAssets.contains('third_party_licenses/THIRD_PARTY_LICENSES.txt')) {
        items.add(
          LicenseItem(
            'Third-Party Licenses',
            'third_party_licenses/THIRD_PARTY_LICENSES.txt',
          ),
        );
      }

      // 2. Extraemos todos los archivos sueltos de la carpeta (ej. requests, http)
      final thirdPartyFiles = allAssets.where(
        (path) =>
            path.startsWith('third_party_licenses/') &&
            !path.endsWith('/') &&
            !path.endsWith("THIRD_PARTY_LICENSES.txt"),
      );

      for (final path in thirdPartyFiles) {
        final fileName = path
            .split('/')
            .last; // Sacamos solo el nombre (ej. "requests")
        items.add(LicenseItem(fileName, path));
      }

      setState(() {
        _licenses = items;
        if (_licenses.isNotEmpty) {
          _selectedLicense = _licenses
              .first; // Seleccionamos la primera por defecto para el modo PC
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando manifiesto de licencias: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    return Scaffold(
      appBar: AppBar(title: Text(locale.lTitle)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // MAGIA RESPONSIVA: Si el ancho es mayor a 600, partimos la pantalla
                final isWide = constraints.maxWidth > 600;

                if (isWide) {
                  return Row(
                    children: [
                      // MAESTRO (Lista a la izquierda)
                      SizedBox(width: 300, child: _buildListView(isWide: true)),
                      const VerticalDivider(width: 1, thickness: 1),
                      // DETALLE (Texto a la derecha)
                      Expanded(
                        child: _selectedLicense == null
                            ? Center(child: Text(locale.lButtonSelect))
                            : _LicenseTextViewer(
                                key: ValueKey(_selectedLicense!.assetPath),
                                license: _selectedLicense!,
                              ),
                      ),
                    ],
                  );
                } else {
                  // MÓVIL (Solo lista, empuja el detalle a una nueva pantalla)
                  return _buildListView(isWide: false);
                }
              },
            ),
    );
  }

  Widget _buildListView({required bool isWide}) {
    return ListView.builder(
      itemCount: _licenses.length,
      itemBuilder: (context, index) {
        final item = _licenses[index];
        final isSelected =
            isWide && _selectedLicense?.assetPath == item.assetPath;

        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          selected: isSelected,
          selectedTileColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.3),
          onTap: () {
            if (isWide) {
              // Modo PC: Solo cambiamos el estado y la parte derecha se actualiza
              setState(() => _selectedLicense = item);
            } else {
              // Modo Móvil: Abrimos una nueva pantalla completa
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: Text(item.title)),
                    body: _LicenseTextViewer(license: item),
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

// ============================================================================
// VISOR DE TEXTO PEREZOSO (FutureBuilder con ScrollController explícito)
// ============================================================================
class _LicenseTextViewer extends StatefulWidget {
  final LicenseItem license;

  const _LicenseTextViewer({super.key, required this.license});

  @override
  State<_LicenseTextViewer> createState() => _LicenseTextViewerState();
}

class _LicenseTextViewerState extends State<_LicenseTextViewer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FutureBuilder evita que el hilo principal se congele
    // al cargar archivos de texto gigantes desde los assets.
    final locale = context.watch<LocaleController>().localeStrings;
    return FutureBuilder<String>(
      future: rootBundle.loadString(
        widget.license.assetPath,
      ), // Ojo aquí: widget.license
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('${locale.lLoadingError}: ${snapshot.error}'),
          );
        }

        return Scrollbar(
          controller: _scrollController, // Vinculamos la barra...
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController, // ...con el contenido!
            padding: const EdgeInsets.all(24.0),
            child: SelectableText(
              snapshot.data ?? locale.lEmptyFile,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        );
      },
    );
  }
}
