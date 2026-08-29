import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CobroDialog extends StatefulWidget {
  final double totalUSD;
  final double tasaCambio;
  final bool? tasaEsBCV;

  const CobroDialog({
    super.key,
    required this.totalUSD,
    required this.tasaCambio,
    this.tasaEsBCV,
  });

  @override
  State<CobroDialog> createState() => _CobroDialogState();
}

class _CobroDialogState extends State<CobroDialog> {
  final _usdEfectivoController = TextEditingController(text: '0.00');
  final _vesEfectivoController = TextEditingController(text: '0.00');
  final _pagoMovilController = TextEditingController(text: '0.00');
  final _puntoVentaController = TextEditingController(text: '0.00');

  double get _totalVES => widget.totalUSD * widget.tasaCambio;

  double get _montoUsdEfectivo =>
      double.tryParse(_usdEfectivoController.text) ?? 0.0;
  double get _montoVesEfectivo =>
      double.tryParse(_vesEfectivoController.text) ?? 0.0;
  double get _montoPagoMovil =>
      double.tryParse(_pagoMovilController.text) ?? 0.0;
  double get _montoPuntoVenta =>
      double.tryParse(_puntoVentaController.text) ?? 0.0;

  double get _totalRecibidoUSD =>
      _montoUsdEfectivo +
      ((_montoVesEfectivo + _montoPagoMovil + _montoPuntoVenta) /
          widget.tasaCambio);

  double get _diferenciaUSD => _totalRecibidoUSD - widget.totalUSD;
  double get _diferenciaVES => _diferenciaUSD * widget.tasaCambio;

  bool get _pagoCompleto => _diferenciaUSD >= -0.01;

  void _completarMontoExactoUSD() {
    setState(() {
      _usdEfectivoController.text = widget.totalUSD.toStringAsFixed(2);
      _vesEfectivoController.text = '0.00';
      _pagoMovilController.text = '0.00';
      _puntoVentaController.text = '0.00';
    });
  }

  void _completarMontoExactoVES() {
    setState(() {
      _usdEfectivoController.text = '0.00';
      _vesEfectivoController.text = _totalVES.toStringAsFixed(2);
      _pagoMovilController.text = '0.00';
      _puntoVentaController.text = '0.00';
    });
  }

  @override
  void dispose() {
    _usdEfectivoController.dispose();
    _vesEfectivoController.dispose();
    _pagoMovilController.dispose();
    _puntoVentaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Modulo de Cobro y Pago',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Chip(
                  avatar: const Icon(Icons.currency_exchange, size: 16),
                  label: Text(
                    widget.tasaEsBCV == true
                        ? 'Tasa BCV: ${widget.tasaCambio.toStringAsFixed(2)} Bs/\$'
                        : 'Tasa: ${widget.tasaCambio.toStringAsFixed(2)} Bs/\$ (respaldo)',
                  ),
                  backgroundColor:
                      (widget.tasaEsBCV == true)
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                ),
              ],
            ),
            const Divider(),
            // Resumen de Totales
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Total USD',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        '\$${widget.totalUSD.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const VerticalDivider(),
                  Column(
                    children: [
                      const Text(
                        'Total VES',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        'Bs. ${_totalVES.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Atajos rápidos
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _completarMontoExactoUSD,
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: const Text('Exacto USD'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _completarMontoExactoVES,
                  icon: const Icon(Icons.money, size: 16),
                  label: const Text('Exacto Bs'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Campos de Pago
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _usdEfectivoController,
                    label: 'Efectivo (\$ USD)',
                    icon: Icons.payments,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInputField(
                    controller: _vesEfectivoController,
                    label: 'Efectivo (Bs. VES)',
                    icon: Icons.money_off,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _pagoMovilController,
                    label: 'Pago Móvil (Bs.)',
                    icon: Icons.phone_android,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInputField(
                    controller: _puntoVentaController,
                    label: 'Punto de Venta (Bs.)',
                    icon: Icons.credit_card,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bloque de Vuelto / Restante
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pagoCompleto
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pagoCompleto ? Colors.green : Colors.red,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _pagoCompleto ? 'CAMBIO / VUELTO:' : 'FALTA POR PAGAR:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _pagoCompleto
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${_diferenciaUSD.abs().toStringAsFixed(2)} USD',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _pagoCompleto
                              ? Colors.green.shade900
                              : Colors.red.shade900,
                        ),
                      ),
                      Text(
                        'Bs. ${_diferenciaVES.abs().toStringAsFixed(2)} VES',
                        style: TextStyle(
                          fontSize: 12,
                          color: _pagoCompleto
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _pagoCompleto
                        ? () {
                            Navigator.of(context).pop({
                              'montoPagadoUSD': _totalRecibidoUSD,
                              'vueltoUSD': _diferenciaUSD > 0
                                  ? _diferenciaUSD
                                  : 0.0,
                              'vueltoVES': _diferenciaVES > 0
                                  ? _diferenciaVES
                                  : 0.0,
                              'detallesPago': {
                                'efectivoUSD': _montoUsdEfectivo,
                                'efectivoVES': _montoVesEfectivo,
                                'pagoMovil': _montoPagoMovil,
                                'puntoVenta': _montoPuntoVenta,
                              },
                              'tasaCambio': widget.tasaCambio,
                            });
                          }
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('CONFIRMAR PAGO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}
