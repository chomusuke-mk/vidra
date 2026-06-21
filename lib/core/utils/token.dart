import 'dart:math';

String generarTokenAleatorio([int length = 48]) {
  const String caracteres =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  Random random = Random.secure();

  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => caracteres.codeUnitAt(random.nextInt(caracteres.length)),
    ),
  );
}
