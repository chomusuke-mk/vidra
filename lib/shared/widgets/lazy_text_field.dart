import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';

/// ponytail: Se reincorpora filesystem_picker como alternativa opcional.
/// El atajo (shortcut) aquí es la resolución del rootDirectory:
/// En lugar de cientos de líneas intentando adivinar las unidades del sistema,
/// la heurística parte de la ruta que el usuario ya tenga en el campo de texto,
/// de su directorio padre, o del directorio actual como último recurso.
class LazyTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;

  final bool isNumeric;
  final bool pickDirectory;
  final bool pickFile;
  final bool readOnly;

  // Opciones: "file_picker" (por defecto) o "filesystem_picker"
  final String library;

  LazyTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.isNumeric = false,
    this.pickDirectory = false,
    this.pickFile = false,
    String library = 'file_picker',
    this.readOnly = false,
  }) : assert(
         !(pickDirectory && pickFile),
         'No puedes seleccionar archivo y carpeta a la vez.',
       ),
       assert(
         library == 'file_picker' || library == 'filesystem_picker',
         'Librería no soportada',
       ),
       library =
           library == 'filesystem_picker' &&
               !(Platform.isAndroid || Platform.isIOS)
           ? 'file_picker'
           : library;

  @override
  State<LazyTextField> createState() => _LazyTextFieldState();
}

class _LazyTextFieldState extends State<LazyTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant LazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  void _submit() {
    if (_controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  void _adjustNumber(int delta) {
    final current = int.tryParse(_controller.text) ?? 0;
    _controller.text = (current + delta).toString();
    _submit();
  }

  Future<void> _pickPath() async {
    try {
      String? path;

      if (widget.library == 'filesystem_picker') {
        // --- Lógica Filesystem Picker ---
        Directory root = Directory.current;

        // Intentamos usar la ruta actual como punto de partida
        if (_controller.text.isNotEmpty) {
          final dir = Directory(_controller.text);
          if (dir.existsSync()) {
            root = dir;
          } else if (dir.parent.existsSync()) {
            root = dir.parent; // Útil si era un archivo
          }
        }

        path = await FilesystemPicker.open(
          context: context,
          rootDirectory: root,
          fsType: widget.pickDirectory
              ? FilesystemType.folder
              : FilesystemType.file,
          title: widget.label ?? 'Seleccionar',
          folderIconColor: Theme.of(context).colorScheme.primary,
        );
      } else {
        // --- Lógica File Picker ---
        if (widget.pickDirectory) {
          path = await FilePicker.getDirectoryPath(dialogTitle: widget.label);
        } else {
          final result = await FilePicker.pickFiles(dialogTitle: widget.label);
          path = result?.files.single.path;
        }
      }

      if (path != null) {
        _controller.text = path;
        _submit();
      }
    } catch (e) {
      debugPrint('Error al seleccionar ruta con ${widget.library}: $e');
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly,
      keyboardType: widget.isNumeric
          ? TextInputType.number
          : TextInputType.text,
      inputFormatters: widget.isNumeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onEditingComplete: () {
        _submit();
        _focusNode.unfocus();
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: widget.isNumeric
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => _adjustNumber(1),
                    child: const Icon(Icons.arrow_drop_up, size: 20),
                  ),
                  InkWell(
                    onTap: () => _adjustNumber(-1),
                    child: const Icon(Icons.arrow_drop_down, size: 20),
                  ),
                ],
              )
            : null,
      ),
    );

    if (widget.pickDirectory || widget.pickFile) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              widget.pickDirectory ? Icons.folder_open : Icons.file_present,
            ),
            onPressed: _pickPath,
            tooltip: 'Seleccionar ruta (${widget.library})',
          ),
        ],
      );
    }

    return field;
  }
}
