import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

void main() {
  testWidgets('Añadir, evitar duplicados y eliminar elementos en LazyList', (
    WidgetTester tester,
  ) async {
    List<String> currentList = ['existente'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return LazyList(
                value: currentList,
                onChanged: (newList) => setState(() => currentList = newList),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('existente'), findsOneWidget);

    final textField = find.byType(TextField);
    await tester.enterText(textField, 'nuevo');
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    expect(currentList, ['existente', 'nuevo']);
    expect(find.byType(InputChip), findsNWidgets(2));

    await tester.enterText(textField, 'nuevo');
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    expect(currentList.length, 2);

    // Ahora buscamos por nuestro ícono explícito (es seguro y nativo)
    await tester.tap(find.byIcon(Icons.cancel).first);
    await tester.pumpAndSettle();

    expect(currentList, ['nuevo']);
    expect(find.text('existente'), findsNothing);
  });
}
