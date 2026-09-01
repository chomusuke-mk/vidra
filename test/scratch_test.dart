import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('env', () {
    print(Platform.environment.containsKey('FLUTTER_TEST'));
  });
}
