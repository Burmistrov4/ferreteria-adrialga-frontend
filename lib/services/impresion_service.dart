import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/factura_model.dart';

/// Motor de impresión térmica de tickets (formato 80mm).
///
/// Genera un PDF compacto tipo comprobante (encabezado → metadatos → detalle →
/// totales → pie) y lo envía al diálogo nativo del sistema con [Printing.layoutPdf].
/// Reutiliza [FacturaModel]; si `esNotaCredito` es true, encabeza el documento
/// como NOTA DE CRÉDITO referenciando la factura afectada.
class ImpresionService {
  ImpresionService._();

  // Datos de cabecera del establecimiento (configuración fiscal Adrialga).
  static const String _nombre = 'FERRETERÍA ADRIALGA, C.A.';
  static const String _rif = 'RIF: J-12345678-9';
  static const String _direccion = 'Av. Principal, Local 1';

  static String _fmt(double v) => v.toStringAsFixed(2);

static String _truncar(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String _fmtFecha(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $h:$mi';
  }

  static pw.Widget _ctr(String s,
      {bool bold = false, double size = 9, PdfColor? color}) {
    return pw.Text(
      s,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontSize: size,
        color: color ?? PdfColors.black,
      ),
    );
  }

  static pw.Widget _row(String izq, String der, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(izq,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(der,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static Future<pw.Document> _generar(
    FacturaModel f, {
    required bool esNotaCredito,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (_) => [
          // ── Encabezado del establecimiento ──
          _ctr(_nombre, bold: true, size: 11),
          _ctr(_rif, size: 8, color: PdfColors.grey700),
          _ctr(_direccion, size: 8, color: PdfColors.grey700),
          pw.SizedBox(height: 4),
          pw.Divider(color: PdfColors.black, height: 1),
          pw.SizedBox(height: 4),

          // ── Tipo de documento ──
          _ctr(
            esNotaCredito ? 'NOTA DE CRÉDITO' : 'FACTURA',
            bold: true,
            size: 12,
          ),
          pw.SizedBox(height: 4),
          _row('Nro.',
              '${esNotaCredito ? f.numeroControl ?? f.facturaId : f.facturaId}'),
          if (esNotaCredito)
            _row('Factura afectada', f.numeroControl ?? '${f.facturaId}'),
          _row('Fecha', _fmtFecha(f.fechaEmision)),
          _row('Cliente',
              (f.clienteNombre ?? '').isNotEmpty ? f.clienteNombre! : 'Consumidor Final'),
          _row(
            'RIF/Cédula',
            (f.clienteRif ?? '').isNotEmpty ? f.clienteRif! : 'V-00000000',
          ),
          pw.Divider(color: PdfColors.black, height: 1),
          pw.SizedBox(height: 3),

          // ── Detalle (tabla compacta) ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CANT',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('PRODUCTO',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('P.UNIT',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('SUBT',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Divider(color: PdfColors.black, height: 1),
          pw.SizedBox(height: 2),
          ...f.detalles.map((d) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.SizedBox(
                      width: 28,
                      child: pw.Text('${d.cantidad}',
                          style: const pw.TextStyle(fontSize: 8.5)),
                    ),
                    pw.SizedBox(
                      width: 150,
                      child: pw.Text(_truncar(d.productoNombre, 42),
                          overflow: pw.TextOverflow.clip,
                          style: const pw.TextStyle(fontSize: 8.5)),
                    ),
                    pw.SizedBox(
                      width: 42,
                      child: pw.Text(_fmt(d.precioUnitario),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8.5)),
                    ),
                    pw.SizedBox(
                      width: 42,
                      child: pw.Text(_fmt(d.subtotal),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8.5)),
                    ),
                  ],
                ),
              )),

          pw.SizedBox(height: 4),
          pw.Divider(color: PdfColors.black, height: 1),
          pw.SizedBox(height: 3),

          // ── Totales ──
          _row('Subtotal:', '\$${_fmt(f.subtotal)}'),
          _row('IVA (16%):', '\$${_fmt(f.totalIva)}'),
          if (f.montoIgtf > 0) _row('IGTF (3% div.):', '\$${_fmt(f.montoIgtf)}'),
          _row('Total:', '\$${_fmt(f.totalGeneral)}', bold: true),
          if ((f.tasaCambio ?? 0) > 0)
            _row(
                'Total Bs.',
                'Bs ${_fmt(f.totalGeneral * f.tasaCambio!)}',
                bold: true),
          pw.SizedBox(height: 3),
          pw.Divider(color: PdfColors.black, height: 1),
          pw.SizedBox(height: 3),

          // ── Pie: tasa, métodos de pago y agradecimiento ──
          if ((f.tasaCambio ?? 0) > 0)
            _row('Tasa BCV:', '${f.tasaCambio!.toStringAsFixed(4)} Bs/\$'),
          if (f.pagos.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            _ctr('— Métodos de pago —', size: 8, color: PdfColors.grey700),
            ...f.pagos.map((p) => _row(
                  p.metodo,
                  p.esDivisa
                      ? '\$${_fmt(p.monto)}'
                      : 'Bs ${_fmt(p.monto)}',
                )),
          ],
          pw.SizedBox(height: 10),
          _ctr('¡Gracias por su compra!', size: 9, bold: true),
          _ctr('Adrialga · Sistema POS', size: 7, color: PdfColors.grey700),
        ],
      ),
    );

    return doc;
  }

  /// Imprime el ticket térmico de una factura o Nota de Crédito.
  static Future<void> imprimirTicketFactura(
    FacturaModel factura, {
    bool esNotaCredito = false,
  }) async {
    final doc = await _generar(factura, esNotaCredito: esNotaCredito);
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'ticket_${esNotaCredito ? 'NC' : 'FAC'}_${factura.numeroControl ?? factura.facturaId}.pdf',
    );
  }
}