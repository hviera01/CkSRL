import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso:\n'
        '  dart tool/supabase_sql.dart <archivo.sql>\n'
        '  dart tool/supabase_sql.dart -c "<sql>"');
    exit(2);
  }

  final env = _leerEnv();
  final token = env['SUPABASE_ACCESS_TOKEN'];
  final ref = env['SUPABASE_PROJECT_REF'];

  if (token == null || token.isEmpty || ref == null || ref.isEmpty) {
    stderr.writeln('Faltan SUPABASE_ACCESS_TOKEN y/o SUPABASE_PROJECT_REF en .env '
        '(ver .env.example).');
    exit(2);
  }

  final sql = args.first == '-c'
      ? args.skip(1).join(' ')
      : File(args.first).readAsStringSync();

  final client = HttpClient();
  final req = await client.postUrl(
    Uri.parse('https://api.supabase.com/v1/projects/$ref/database/query'),
  );
  req.headers.set('Authorization', 'Bearer $token');
  req.headers.set('Content-Type', 'application/json');
  req.add(utf8.encode(jsonEncode({'query': sql})));

  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  client.close();

  stdout.writeln('HTTP ${res.statusCode}');
  try {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(jsonDecode(body)));
  } catch (_) {
    stdout.writeln(body);
  }
  if (res.statusCode >= 300) exit(1);
}

Map<String, String> _leerEnv() {
  final archivo = File('.env');
  if (!archivo.existsSync()) return {};
  final valores = <String, String>{};
  for (final linea in archivo.readAsLinesSync()) {
    final l = linea.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final i = l.indexOf('=');
    if (i <= 0) continue;
    valores[l.substring(0, i).trim()] = l.substring(i + 1).trim();
  }
  return valores;
}
