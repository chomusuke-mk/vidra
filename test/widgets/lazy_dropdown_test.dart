import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Ajusta a tu ruta real
import 'package:vidra/shared/widgets/lazy_text_field.dart';

void main() {
  testWidgets('Envía el valor modificado al perder el foco (onSubmitted)', (
    WidgetTester tester,
  ) async {
    String valorGuardado = 'inicio';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return LazyTextField(
                value: valorGuardado,
                onChanged: (val) => setState(() => valorGuardado = val),
              );
            },
          ),
        ),
      ),
    );

    final textField = find.byType(TextField);

    await tester.enterText(textField, 'nuevo texto');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(valorGuardado, 'nuevo texto');
  });

  testWidgets('El spinner incrementa y decrementa correctamente el valor', (
    WidgetTester tester,
  ) async {
    String valorState = '10';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // ponytail: Simulamos el estado real de la app.
          // Cada vez que onChanged emite, el widget padre se reconstruye con el nuevo valor.
          body: StatefulBuilder(
            builder: (context, setState) {
              return LazyTextField(
                value: valorState,
                isNumeric: true,
                onChanged: (val) => setState(() => valorState = val),
              );
            },
          ),
        ),
      ),
    );

    // 1. Probamos incrementar
    await tester.tap(find.byIcon(Icons.arrow_drop_up));
    await tester.pumpAndSettle();
    expect(valorState, '11');

    // 2. Probamos decrementar
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(
      valorState,
      '10',
    ); // Ahora sí reconoce el cambio porque su state base era 11
  });
}
