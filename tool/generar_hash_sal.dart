import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final clave = args.first;
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final sal = base64UrlEncode(bytes);
  final hash = sha256.convert(utf8.encode('$sal:$clave')).toString();
  print('sal=$sal');
  print('hash=$hash');
}
