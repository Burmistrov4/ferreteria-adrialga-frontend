import 'dart:async';
import 'dart:html' as html;

/// Abre el selector de archivos del navegador y devuelve los bytes + MIME.
/// Solo se compila en web (el stub cubre las demás plataformas).
Future<({List<int> bytes, String mime})?> elegirImagen() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) return null;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;
  final bytes = reader.result as List<int>;
  return (
    bytes: bytes,
    mime: file.type.isEmpty ? 'image/png' : file.type,
  );
}
