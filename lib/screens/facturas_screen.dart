import 'package:flutter/material.dart';

import '../models/factura_model.dart';
import '../services/api_service.dart';
import '../services/factura_pdf_service.dart';
import '../widgets/factura_detalle_dialog.dart';

/// Registro de Facturas: historial de ventas con opción de imprimir en PDF.
class FacturasScreen extends StatefulWidget {
  const FacturasScreen({super.key});

  @override
  State<FacturasScreen> createState() => _FacturasScreenState();
}

class _FacturasScreenState extends State<FacturasScreen> {
  List<FacturaModel> _facturas = [];
  bool _isLoading = true;
  String _query = '';
  double _tasa = 36.50;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getFacturas();
      _tasa = ApiService.lastTasa;
      if (mounted) {
        setState(() {
          _facturas = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar facturas: $e')));
      }
    }
  }

  List<FacturaModel> get _filtradas {
    if (_query.isEmpty) return _facturas;
    final q = _query.toLowerCase();
    return _facturas.where((f) {
      final nc = (f.numeroControl ?? '').toLowerCase();
      final cl = (f.clienteNombre ?? '').toLowerCase();
      return nc.contains(q) || cl.contains(q);
    }).toList();
  }

  Future<void> _verDetalle(FacturaModel f) async {
    await showDialog<void>(
      context: context,
      builder: (_) => FacturaDetalleDialog(factura: f, tasa: _tasa),
    );
  }

  String _fmtFecha(DateTime? dt) {
    if (dt == null) return '---';
    return '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Facturas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por N° de control o cliente',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: _filtradas.isEmpty
                      ? const Center(child: Text('No hay facturas registradas'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _filtradas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final f = _filtradas[index];
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                onTap: () => _verDetalle(f),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.withOpacity(
                                    0.12,
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long,
                                    color: Colors.blue,
                                  ),
                                ),
                                title: Text(
                                  '${f.numeroControl ?? "FV-${f.facturaId}"} • ${f.clienteNombre!.isNotEmpty ? f.clienteNombre : "Consumidor Final"}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_fmtFecha(f.fechaEmision)} • \$${f.totalGeneral.toStringAsFixed(2)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'Ver detalle',
                                      onPressed: () => _verDetalle(f),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.print,
                                        color: Colors.green,
                                      ),
                                      tooltip: 'Imprimir',
                                      onPressed: () =>
                                          FacturaPdfService.imprimir(
                                            f,
                                            tasa: _tasa,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
