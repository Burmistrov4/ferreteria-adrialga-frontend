import 'package:flutter/material.dart';

import '../models/factura_model.dart';
import '../services/api_service.dart';
import '../services/factura_pdf_service.dart';
import '../services/impresion_service.dart';
import 'supervisor_override_dialog.dart';

/// Diálogo con el detalle de una factura y botones de imprimir / guardar PDF.
class FacturaDetalleDialog extends StatelessWidget {
  final FacturaModel factura;
  final double tasa;

  const FacturaDetalleDialog({super.key, required this.factura, required this.tasa});

  static String _fmtFecha(DateTime? dt) {
    if (dt == null) return '---';
    final d = dt.day.toString().padLeft(2, "0");
    final m = dt.month.toString().padLeft(2, "0");
    final h = dt.hour.toString().padLeft(2, "0");
    final mi = dt.minute.toString().padLeft(2, "0");
    final s = dt.second.toString().padLeft(2, "0");
    return '$d/$m/${dt.year} $h:$mi:$s';
  }

  /// La reversión solo es válida sobre ventas procesadas (Pagada/Completada).
  bool get _esReversible =>
      factura.estatus == 'Pagada' || factura.estatus == 'Completada';

  /// Flujo de "Reversar Venta" (P0.4): confirmación obligatoria → POST →
  /// manejo del déficit de caja (SALDO_INSUFICIENTE).
  Future<void> _reversar(BuildContext context) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
        title: const Text('¿Reversar esta venta?'),
        content: const Text(
          'Esta acción es irreversible. Se emitirá una Nota de Crédito fiscal, '
          'se retornarán los artículos al inventario recalculando su costo, y se '
          'registrará un egreso en la caja actual por el monto de la venta. '
          '¿Desea continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, reversar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    // Autorización en caliente: un CAJERO debe validar su PIN contra el
    // backend (Supervisor/Admin) antes de poder reversar.
    String? pinSupervisor;
    if (!ApiService.esSupervisor) {
      pinSupervisor = await showDialog<String>(
        context: context,
        builder: (_) => const SupervisorOverrideDialog(),
      );
      if (pinSupervisor == null || !context.mounted) return; // cancelado
      final valida = await ApiService.validarPinSupervisor(pinSupervisor);
      if (!context.mounted) return;
      if (valida['valido'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN de Supervisor inválido'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final resultado =
        await ApiService.reversarVenta(factura.facturaId, pinSupervisor: pinSupervisor);
    if (!context.mounted) return;

    if (resultado['success'] == true) {
      final nc = (resultado['notaCredito'] as Map?) ?? const {};
      final ncCtrl = nc['Numero_Control'] ?? nc['numeroControl'] ?? '';
      Navigator.of(context).pop(); // cierra el detalle
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ncCtrl.toString().isEmpty
                ? 'Venta reversada: Nota de Crédito emitida'
                : 'Venta reversada: Nota de Crédito $ncCtrl emitida',
          ),
        ),
      );
      return;
    }

    // Error de déficit o PIN inválido reportado por el backend.
    if (resultado['tipo'] == 'SALDO_INSUFICIENTE') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.liquor, color: Colors.orange, size: 48),
          title: const Text('Saldo insuficiente en caja'),
          content: Text(
            '${resultado['error']}\n\n'
            'Solicite un "Ingreso de Caja" al supervisor sobre el arqueo actual '
            'antes de poder devolver el dinero de esta factura.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final esPin = resultado['tipo'] == 'SUPERVISOR_REQUERIDO' ||
        resultado['tipo'] == 'PIN_INVALIDO';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          esPin ? 'PIN de Supervisor inválido' : (resultado['error']?.toString() ?? 'No se pudo reversar la venta'),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = factura;
    final anchoPantalla = MediaQuery.of(context).size.width;
    final esMovil = anchoPantalla < 600;
    
    return Dialog(
      insetPadding: esMovil 
          ? const EdgeInsets.all(8)
          : EdgeInsets.symmetric(horizontal: anchoPantalla * 0.1, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: esMovil ? anchoPantalla : 520,
        padding: EdgeInsets.all(esMovil ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Detalle de Factura',
                    style: TextStyle(
                      fontSize: esMovil ? 16 : 18, 
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  f.numeroControl ?? 'FV-${f.facturaId}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: esMovil ? 12 : 14,
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              'Cliente: ${f.clienteNombre!.isNotEmpty ? f.clienteNombre : "Consumidor Final"}',
              style: TextStyle(fontSize: esMovil ? 11 : 13),
            ),
            Text(
              'RIF/Cédula: ${f.clienteRif!.isNotEmpty ? f.clienteRif : "V-00000000"}',
              style: TextStyle(fontSize: esMovil ? 11 : 13),
            ),
            Text(
              'Fecha: ${_fmtFecha(f.fechaEmision)} • Atendido por: ${f.usuarioNombre!.isNotEmpty ? f.usuarioNombre : "Administrador"}',
              style: TextStyle(fontSize: esMovil ? 11 : 13),
            ),
            SizedBox(height: esMovil ? 6 : 10),
            Flexible(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: esMovil ? 12 : 18,
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
                        DataCell(Text(d.productoNombre, style: TextStyle(fontSize: esMovil ? 11 : 13))),
                        DataCell(Text('${d.cantidad}', style: TextStyle(fontSize: esMovil ? 11 : 13))),
                        DataCell(Text('\$${d.precioUnitario.toStringAsFixed(2)}', style: TextStyle(fontSize: esMovil ? 11 : 13))),
                        DataCell(Text('\$${d.subtotal.toStringAsFixed(2)}', style: TextStyle(fontSize: esMovil ? 11 : 13))),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
            if (f.pagos.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Forma de Pago (desglose):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...f.pagos.map((p) {
                final bs = p.enBolivares(f.tasaCambio ?? 0);
                return _row(
                  '${p.metodo}${p.esDivisa ? " (USD)" : " (Bs)"}',
                  'Bs. ${bs.toStringAsFixed(2)}'
                      '${p.esDivisa ? "  •  IGTF 3%" : ""}',
                );
              }),
            ],
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
            // Botones responsivos: en móvil se apilan
            esMovil
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt, size: 18),
                        onPressed: () => FacturaPdfService.guardarYVer(f, tasa: tasa),
                        label: const Text('Guardar PDF'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.print, size: 18),
                        onPressed: () => FacturaPdfService.imprimir(f, tasa: tasa),
                        label: const Text('Imprimir'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_long, size: 18),
                        onPressed: () => ImpresionService.imprimirTicketFactura(
                          f,
                          esNotaCredito: f.estatus == 'Reversada',
                        ),
                        label: const Text('Imprimir Ticket'),
                      ),
                      if (_esReversible) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          icon: const Icon(Icons.undo, size: 18),
                          onPressed: () => _reversar(context),
                          label: const Text('Reversar Venta'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_esReversible)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          icon: const Icon(Icons.undo, size: 18),
                          onPressed: () => _reversar(context),
                          label: const Text('Reversar Venta'),
                        ),
                      const SizedBox(width: 8),
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
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_long, size: 18),
                        onPressed: () => ImpresionService.imprimirTicketFactura(
                          f,
                          esNotaCredito: f.estatus == 'Reversada',
                        ),
                        label: const Text('Imprimir Ticket'),
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