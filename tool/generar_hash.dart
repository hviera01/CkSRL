import 'dart:convert';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final clave = args.first;
  final hash = sha256.convert(utf8.encode(clave)).toString();
  print(hash);
}