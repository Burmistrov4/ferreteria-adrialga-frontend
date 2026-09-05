import 'dart:typed_data';

import 'download_service_stub.dart'
    if (dart.library.html) 'download_service_web.dart'
    if (dart.library.io) 'download_service_mobile.dart';

/// Servicio de descarga universal que maneja Web y Mobile/Desktop.
///
/// En Web: usa AnchorElement con Blob para forzar descarga en el navegador.
/// En Mobile/Desktop: usa path_provider + File para guardar en el sistema de archivos.
class DownloadService {
  /// Descarga un archivo con los [bytes] proporcionados y el [filename] indicado.
  static Future<void> downloadFile({
    required Uint8List bytes,
    required String filename,
    String mimeType = 'application/octet-stream',
  }) async {
    await downloadImpl(bytes: bytes, filename: filename, mimeType: mimeType);
  }
}
