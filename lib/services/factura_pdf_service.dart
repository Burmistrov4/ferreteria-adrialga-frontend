import 'dart:io';
import 'dart:typed_data';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/factura_model.dart';

/// Genera, imprime y guarda facturas en formato PDF.
class FacturaPdfService {
  static const PdfColor _azul = PdfColor.fromInt(0xFF1565C0);
  static const PdfColor _gris = PdfColor.fromInt(0xFF616161);

  static String _fmt(double v) => v.toStringAsFixed(2);

  /// Formatea con separador de miles y 2 decimales para montos en Bs.
  static String _fmtMoneda(double v) {
    final partes = v.toStringAsFixed(2).split('.');
    final enteros = partes[0];
    final buf = StringBuffer();
    for (var i = 0; i < enteros.length; i++) {
      if (i > 0 && (enteros.length - i) % 3 == 0) buf.write('.');
      buf.write(enteros[i]);
    }
    return '${buf.toString()},${partes[1]}';
  }

  /// Tasa a usar para el comprobante: prioriza la tasa BCV HISTÓRICA
  /// persistida en la factura; si no está disponible, usa la tasa actual
  /// que se recibe como parámetro (fallback para facturas viejas sin dato).
  static double _tasaPersistida(FacturaModel f, {double fallback = 0}) {
    final historica = f.tasaCambio;
    if (historica != null && historica > 0) return historica;
    return fallback > 0 ? fallback : 0;
  }

  static Future<Uint8List> _generar(
    FacturaModel f, {
    required double tasa,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.RichText(
                  text: pw.TextSpan(
                    text: 'FERRETERÍA ADRIALGA C.A.',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: _azul,
                    ),
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'FACTURA',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _azul,
                      ),
                    ),
                    pw.Text(
                      'N° ${f.numeroControl ?? f.facturaId}',
                      style: const pw.TextStyle(fontSize: 11, color: _gris),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: _azul, thickness: 1.2),
            pw.SizedBox(height: 4),
            pw.Text(
              'RIF: J-12345678-9  •  Dirección: Av. Principal, Local 1',
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(color: _gris, fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _azul, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Cliente: ${f.clienteNombre!.isNotEmpty ? f.clienteNombre : "Consumidor Final"}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.Text(
                      'Fecha: ${_fmtFecha(f.fechaEmision)}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'RIF/Cédula: ${f.clienteRif!.isNotEmpty ? f.clienteRif : "V-00000000"}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.Text(
                      'Atendido por: ${f.usuarioNombre!.isNotEmpty ? f.usuarioNombre : "Administrador"}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['Código', 'Descripción', 'Cant.', 'P. Unit.', 'Subtotal (\$)'],
            data: f.detalles.map((d) {
              return [
                d.productoSkU,
                d.productoNombre,
                '${d.cantidad}',
                _fmt(d.precioUnitario),
                _fmt(d.subtotal),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: _azul),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 230,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _filaTotal('Base Imponible', _fmt(f.subtotal)),
                  _filaTotal('IVA (16%)', _fmt(f.totalIva)),
                  if (f.montoIgtf > 0)
                    _filaTotal(
                      'IGTF (3% divisas)',
                      '${_fmt(f.montoIgtf)} USD',
                    ),
                  pw.Divider(color: _azul),
                  _filaTotal('TOTAL', '${_fmt(f.totalGeneral)} USD', bold: true),
                  pw.SizedBox(height: 6),
                  // Tasa histórica (de la factura persistida). Si no está
                  // disponible, cae al valor actual que se pasa como parámetro.
                  pw.Text(
                    'Tasa BCV (histórica): ${_tasaPersistida(f, fallback: tasa).toStringAsFixed(4)} Bs/\$',
                    style: const pw.TextStyle(fontSize: 9, color: _gris),
                  ),
                  pw.Text(
                    'Total en Bs: ${_fmtMoneda(f.totalGeneral * _tasaPersistida(f, fallback: tasa))} Bs',
                    style: const pw.TextStyle(fontSize: 9, color: _gris),
                  ),
                  if (f.montoIgtf > 0)
                    pw.Text(
                      'IGTF en Bs: ${_fmtMoneda(f.montoIgtf * _tasaPersistida(f, fallback: tasa))} Bs',
                      style: const pw.TextStyle(fontSize: 9, color: _gris),
                    ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            '¡Gracias por su compra!',
            style: pw.TextStyle(
              fontSize: 12,
              color: _gris,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }
  static pw.Widget _filaTotal(String label, String value,
      {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: bold ? 14 : 11,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: bold ? 14 : 11,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtFecha(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  /// Abre el diálogo de impresión del sistema.
  static Future<void> imprimir(FacturaModel f, {required double tasa}) async {
    final bytes = await _generar(f, tasa: tasa);
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'factura_${f.numeroControl ?? f.facturaId}.pdf',
    );
  }

  /// Guarda el PDF en Documentos y lo abre con la app por defecto.
  static Future<void> guardarYVer(
    FacturaModel f, {
    required double tasa,
  }) async {
    final bytes = await _generar(f, tasa: tasa);
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/factura_${f.numeroControl ?? f.facturaId}.pdf');
    await file.writeAsBytes(bytes);
    await OpenFile.open(file.path);
  }
}