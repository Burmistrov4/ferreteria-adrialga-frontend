import 'dart:typed_data';

/// Stub implementation para plataformas no soportadas.
Future<void> downloadImpl({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('Descarga no soportada en esta plataforma');
}
