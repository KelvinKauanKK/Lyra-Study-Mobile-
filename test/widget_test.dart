import 'package:flutter_test/flutter_test.dart';
import 'package:lyra_study_mobile/state/admin_secret.dart'; // ajuste o nome do package se for diferente no pubspec.yaml

void main() {
  test('senha admin inválida retorna false', () {
    expect(verifyAdminPassword('senha_incorreta_123'), isFalse);
  });
}