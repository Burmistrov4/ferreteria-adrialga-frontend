import 'package:flutter/material.dart';

import '../models/factura_model.dart';
import '../services/api_service.dart';
import '../services/factura_pdf_service.dart';
import '../widgets/factura_detalle_dialog.dart';

/// Registro de Facturas: historial de ventas con opción de imprimir en PDF.
/// Acepta [periodoInicial] ('hoy' | 'semana' | 'mes' | 'anio') para iniciar
/// con un filtro temporal ya aplicado (navegación cruzada desde el Dashboard).
class FacturasScreen extends StatefulWidget {
  final String? periodoInicial;

  const FacturasScreen({super.key, this.periodoInicial});

  @override
  State<FacturasScreen> createState() => _FacturasScreenState();
}

class _FacturasScreenState extends State<FacturasScreen> {
  List<FacturaModel> _facturas = [];
  bool _isLoading = true;
  String _query = '';
  double _tasa = 36.50;

  // ── Filtro temporal ─────────────────────────────────────────────────────
  // 'todas' | 'hoy' | 'semana' | 'mes' | 'anio' | 'personalizado'
  String _filtro = 'todas';
  DateTimeRange? _rangoCustom;

  static const _filtrosRapidos = <(String, String)>[
    ('todas', 'Todas'),
    ('hoy', 'Hoy'),
    ('semana', 'Esta Semana'),
    ('mes', 'Este Mes'),
    ('anio', 'Este Año'),
  ];

  @override
  void initState() {
    super.initState();
    final inicial = widget.periodoInicial;
    if (inicial != null &&
        ['hoy', 'semana', 'mes', 'anio'].contains(inicial)) {
      _filtro = inicial;
    }
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getFacturas(
        periodo: _filtro == 'personalizado' || _filtro == 'todas'
            ? null
            : _filtro,
        desde: _filtro == 'personalizado' ? _rangoCustom?.start : null,
        hasta: _filtro == 'personalizado' ? _rangoCustom?.end : null,
      );
      _tasa = ApiService.lastTasa;
      if (mounted) {
        setState(() {
          _facturas = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar facturas: $e'),
            backgroundColor: cs.error,
          ),
        );
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

  // ── Barra de filtros temporales ───────────────────────────────────────────

  Future<void> _seleccionarPersonalizado() async {
    final hoy = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 5),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      initialDateRange: _rangoCustom,
      helpText: 'SELECCIONE EL RANGO DE FECHAS',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      locale: const Locale('es', 'VE'),
    );
    if (rango == null) return;
    setState(() {
      _filtro = 'personalizado';
      _rangoCustom = rango;
    });
    _cargar();
  }

  void _seleccionarFiltro(String filtro) {
    if (filtro == 'personalizado') {
      _seleccionarPersonalizado();
      return;
    }
    if (filtro == _filtro) return;
    setState(() => _filtro = filtro);
    _cargar();
  }

  Widget _buildBarraFiltros(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._filtrosRapidos.map((f) {
            final sel = _filtro == f.$1;
            return ChoiceChip(
              label: Text(f.$2),
              selected: sel,
              selectedColor: cs.primaryContainer,
              labelStyle: TextStyle(
                color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) => _seleccionarFiltro(f.$1),
            );
          }),
          ChoiceChip(
            avatar: Icon(
              Icons.date_range,
              size: 18,
              color: _filtro == 'personalizado' ? cs.onPrimaryContainer : cs.outline,
            ),
            label: Text(
              _filtro == 'personalizado' && _rangoCustom != null
                  ? '${_fmtFecha(_rangoCustom!.start)} - ${_fmtFecha(_rangoCustom!.end)}'
                  : 'Personalizado',
            ),
            selected: _filtro == 'personalizado',
            selectedColor: cs.primaryContainer,
            labelStyle: TextStyle(
              color: _filtro == 'personalizado'
                  ? cs.onPrimaryContainer
                  : cs.onSurfaceVariant,
              fontWeight: _filtro == 'personalizado'
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
            onSelected: (_) => _seleccionarFiltro('personalizado'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          leading: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Regresar',
            onPressed: () => Navigator.maybePop(context),
          ),
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
                  _buildBarraFiltros(context),
                  Expanded(
                    child: _filtradas.isEmpty
                        ? const Center(child: Text('No hay facturas registradas'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _filtradas.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final f = _filtradas[index];
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  onTap: () => _verDetalle(f),
                                  leading: CircleAvatar(
                                    backgroundColor: cs.primaryContainer,
                                    child: Icon(
                                      Icons.receipt_long,
                                      color: cs.onPrimaryContainer,
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
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        icon: Icon(
                                          Icons.visibility,
                                          color: cs.primary,
                                        ),
                                        tooltip: 'Ver detalle',
                                        onPressed: () => _verDetalle(f),
                                      ),
                                      IconButton(
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        icon: Icon(
                                          Icons.print,
                                          color: cs.secondary,
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
      ),
    );
  }
}
