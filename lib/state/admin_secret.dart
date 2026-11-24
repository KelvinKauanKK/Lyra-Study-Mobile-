import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Acesso Admin (mesma senha fixa do desktop). O código guarda só o HASH (SHA-256 iterado 50.000x com sal), não o texto da senha.
/// Atenção: uma senha curta só serve como trava de teste; os dados do app continuam editáveis por quem tiver acesso ao aparelho.
const _salt = 'f902b38aecbb5949';
const _hash = '9912151d4081bb8481fe25df1eff0584c4bf24c7b22f5e8d17fb9dc96a7bfd60';

bool verifyAdminPassword(String pw) {
  var bytes = utf8.encode('$_salt:$pw');
  for (var i = 0; i < 50000; i++) {
    bytes = sha256.convert(bytes).bytes;
  }
  return Digest(Uint8List.fromList(bytes)).toString() == _hash;
}