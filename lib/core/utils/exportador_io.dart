import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> guardarArchivo(List<int> bytes, String nombreArchivo) async {
  final esEscritorio = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  if (esEscritorio) {
    await FilePicker.saveFile(fileName: nombreArchivo, bytes: Uint8List.fromList(bytes));
    return;
  }
  final directorio = await getTemporaryDirectory();
  final archivo = File('${directorio.path}/$nombreArchivo');
  await archivo.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(archivo.path)]);
}