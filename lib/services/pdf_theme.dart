import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Tema tipográfico PDF (Roboto local) para salida legal UTF-8 (caracteres
/// "ñ" y tildes "áéíóú", símbolos de moneda, etc.) sin dependencia de red.
///
/// Se carga una sola vez (static) desde assets para por-ahorros memoria y
/// evita el FlutterError 'Unable to load asset' en producción si faltara.
class PdfTheme {
  PdfTheme._();

  static pw.ThemeData? _cache;

  /// Devuelve el tema con Roboto regular + bold.
  static Future<pw.ThemeData> regular() async {
    if (_cache != null) return _cache!;
    try {
      final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _cache = pw.ThemeData.withFont(
        base: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
      return _cache!;
    } catch (e) {
      // Fallback a fuente base estándar (Courier) si el asset no está registrado.
      // Degrada a texto plano sin separarse a cero; documenta el estado.
      return pw.ThemeData();
    }
  }
}
