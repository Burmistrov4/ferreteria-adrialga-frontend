import 'package:flutter/material.dart';

import '../models/factura_model.dart';
import '../services/factura_pdf_service.dart';

/// Diálogo con el detalle de una factura y botones de imprimir / guardar PDF.
class FacturaDetalleDialog extends StatelessWidget {
  final FacturaModel factura;
  final double tasa;

  const FacturaDetalleDialog({super.key, required this.factura, required this.tasa});

  static String _fmtFecha(DateTime? dt) {
    if (dt == null) return '---';
    return '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final f = factura;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detalle de Factura',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  f.numeroControl ?? 'FV-${f.facturaId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              'Cliente: ${f.clienteNombre!.isNotEmpty ? f.clienteNombre : "Consumidor Final"}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'RIF/Cédula: ${f.clienteRif!.isNotEmpty ? f.clienteRif : "V-00000000"}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'Fecha: ${_fmtFecha(f.fechaEmision)} • Atendido por: ${f.usuarioNombre!.isNotEmpty ? f.usuarioNombre : "Administrador"}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 18,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 40,
                  columns: const [
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Cant.')),
                    DataColumn(label: Text('Precio')),
                    DataColumn(label: Text('Subtotal')),
                  ],
                  rows: f.detalles.map((d) {
                    return DataRow(cells: [
                      DataCell(Text(d.productoNombre)),
                      DataCell(Text('${d.cantidad}')),
                      DataCell(Text('\$${d.precioUnitario.toStringAsFixed(2)}')),
                      DataCell(Text('\$${d.subtotal.toStringAsFixed(2)}')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            const Divider(),
            _row('Base Imponible:', '\$${f.subtotal.toStringAsFixed(2)}'),
            _row('IVA (16%):', '\$${f.totalIva.toStringAsFixed(2)}'),
            if (f.montoIgtf > 0)
              _row(
                'IGTF (3% div.):',
                '\$${f.montoIgtf.toStringAsFixed(2)} USD'
                '  (Bs. ${(f.montoIgtf * (f.tasaCambio ?? 0)).toStringAsFixed(2)})',
              ),
            _row(
              'Tasa BCV histórica:',
              'Bs. ${(f.tasaCambio ?? 0).toStringAsFixed(4)}',
            ),
            _row(
              'TOTAL:',
              '\$${f.totalGeneral.toStringAsFixed(2)}',
              bold: true,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_alt, size: 18),
                  onPressed: () => FacturaPdfService.guardarYVer(f, tasa: tasa),
                  label: const Text('Guardar PDF'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.print, size: 18),
                  onPressed: () => FacturaPdfService.imprimir(f, tasa: tasa),
                  label: const Text('Imprimir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}