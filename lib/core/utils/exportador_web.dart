import 'dart:html' as html;

Future<void> guardarArchivo(List<int> bytes, String nombreArchivo) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..setAttribute('download', nombreArchivo);
  anchor.click();
  html.Url.revokeObjectUrl(url);
}