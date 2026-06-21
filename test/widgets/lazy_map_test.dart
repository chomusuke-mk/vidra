import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Cambia esto a tu ruta real:
import 'package:vidra/shared/widgets/lazy_map.dart';

void main() {
  testWidgets('Añadir y eliminar una entrada del mapa funciona correctamente', (
    WidgetTester tester,
  ) async {
    Map<String, String> currentMap = {};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return LazyMap(
                value: currentMap,
                onChanged: (newMap) => setState(() => currentMap = newMap),
              );
            },
          ),
        ),
      ),
    );

    // 1. Verificamos que no hay chips inicialmente
    expect(find.byType(InputChip), findsNothing);

    // 2. Llenamos los campos Clave y Valor
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.first, 'Authorization');
    await tester.enterText(textFields.last, 'Bearer 123');

    // 3. Presionamos el botón de añadir (+)
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    // 4. Verificamos que el mapa se actualizó y se renderiza el Chip
    expect(currentMap, {'Authorization': 'Bearer 123'});
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Authorization: Bearer 123'), findsOneWidget);

    // 5. Presionamos el botón de eliminar del InputChip
    // Flutter renderiza el ícono de cerrado internamente en el InputChip
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pumpAndSettle();

    // 6. Verificamos que se eliminó correctamente
    expect(currentMap, isEmpty);
    expect(find.byType(InputChip), findsNothing);
  });
}
