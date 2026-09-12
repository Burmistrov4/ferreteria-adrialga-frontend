import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/caja_turno_tab.dart';

/// Parseo seguro de valores numéricos: Prisma serializa Decimal(18,4) como
/// String en JSON, por lo que nunca se debe castear directo a double.
double _numD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

class FinanzasScreen extends StatefulWidget {
  const FinanzasScreen({super.key});

  @override
  State<FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends State<FinanzasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Regresar',
        ),
        title: const Text('Finanzas & Caja'),
      ),
      body: Column(
        children: [
          Container(
            color: cs.surfaceContainerLow,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: cs.primary,
              tabs: const [
                Tab(icon: Icon(Icons.account_balance), text: 'Caja'),
                Tab(icon: Icon(Icons.trending_up), text: 'Patrimonio'),
                Tab(icon: Icon(Icons.receipt_long), text: 'Cuentas x Pagar'),
                Tab(icon: Icon(Icons.savings), text: 'IVA/SENIAT'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                CajaTurnoTab(),
                _PatrimonioTab(),
                _CuentasPorPagarTab(),
                _SeniatTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatrimonioTab extends StatefulWidget {
  const _PatrimonioTab();
  @override
  State<_PatrimonioTab> createState() => _PatrimonioTabState();
}

class _PatrimonioTabState extends State<_PatrimonioTab> {
  Map<String, dynamic>? _patrimonioData;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPatrimonio();
  }

  Future<void> _cargarPatrimonio() async {
    try {
      final data = await ApiService.getPatrimonioOperativo();
      if (mounted) setState(() { _patrimonioData = data; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_patrimonioData == null) return const Center(child: Text('Error al cargar patrimonio'));
    final caja = _numD(_patrimonioData!['caja']);
    final inventario = _numD(_patrimonioData!['inventario']);
    final patrimonio = _numD(_patrimonioData!['patrimonio']);
    return RefreshIndicator(
      onRefresh: _cargarPatrimonio,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patrimonio Operativo Total', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('\$${patrimonio.toStringAsFixed(2)}', style: TextStyle(color: cs.onSurface, fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Caja Disponible', style: TextStyle(color: cs.onSurface, fontSize: 16)),
                    Text('\$${caja.toStringAsFixed(2)}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                  const Divider(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Valor del Inventario', style: TextStyle(color: cs.onSurface, fontSize: 16)),
                    Text('\$${inventario.toStringAsFixed(2)}', style: TextStyle(color: cs.tertiary, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CuentasPorPagarTab extends StatefulWidget {
  const _CuentasPorPagarTab();
  @override
  State<_CuentasPorPagarTab> createState() => _CuentasPorPagarTabState();
}

class _CuentasPorPagarTabState extends State<_CuentasPorPagarTab> {
  List<dynamic>? _cuentas;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    try {
      final data = await ApiService.getCuentasPorPagar();
      if (mounted) setState(() { _cuentas = data; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; });
    }
  }

  /// Abre el modal "Abonar a Deuda": monto + método de pago. Valida que el
  /// monto no exceda el saldo y delega el update al backend, recargando la
  /// lista al confirmar. Si no hay caja abierta o el PIN falla, lo reporta.
  Future<void> _abrirAbono(int cxpId, double saldo) async {
    final montoCtrl = TextEditingController(text: saldo.toStringAsFixed(2));
    String metodoPago = 'Efectivo';
    bool abonando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Abonar a Deuda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Saldo pendiente: \$${saldo.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: montoCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monto a abonar (\$)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: metodoPago,
                  decoration: const InputDecoration(
                    labelText: 'Método de Pago',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Pago Móvil', child: Text('Pago Móvil')),
                    DropdownMenuItem(value: 'Punto de Venta', child: Text('Punto de Venta')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => metodoPago = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: abonando
                  ? null
                  : () async {
                      final monto = double.tryParse(montoCtrl.text.trim()) ?? 0;
                      if (monto <= 0 || monto > saldo + 0.01) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              monto <= 0
                                  ? 'Ingrese un monto mayor a \$0'
                                  : 'El abono no puede exceder el saldo pendiente',
                            ),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        );
                        return;
                      }
                      setDialog(() => abonando = true);
                      final res = await ApiService.abonarCuentaPorPagar(
                        cxpId,
                        monto,
                        metodoPago,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (res['success'] == true) {
                        _cargarCuentas();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Abono registrado')),
                        );
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res['error']?.toString() ??
                                  'No se pudo registrar el abono',
                            ),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        );
                      }
                    },
              child: abonando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Abonar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_cuentas == null) return const Center(child: Text('Error al cargar cuentas'));
    if (_cuentas!.isEmpty) {
      // Estado vacío amigable (mandato UX: la app se explica sola).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: cs.tertiary),
            const SizedBox(height: 12),
            Text(
              'No hay deudas pendientes',
              style: TextStyle(fontSize: 16, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Las compras a crédito aparecerán aquí.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargarCuentas,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _cuentas!.length,
        itemBuilder: (context, index) {
          final cxp = _cuentas![index];
          final saldo = _numD(cxp['Saldo']);
          final total = _numD(cxp['Monto_Total']);
          final pagado = _numD(cxp['Monto_Pagado']);
          final estatus = cxp['Estatus'] ?? 'Pendiente';
          final prov = cxp['proveedores'] as Map<String, dynamic>?;
          final cxpId = _numD(cxp['CxP_ID']).toInt();
          return Card(
            color: cs.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: estatus == 'Pendiente'
                            ? cs.secondary.withValues(alpha: 0.2)
                            : cs.tertiary.withValues(alpha: 0.2),
                        child: Icon(
                          estatus == 'Pendiente' ? Icons.pending : Icons.check,
                          color: estatus == 'Pendiente'
                              ? cs.secondary
                              : cs.tertiary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prov?['Razon_Social'] ?? 'Proveedor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'CxP #${cxp['CxP_ID']?.toString() ?? ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: estatus == 'Pagada'
                            ? null
                            : () => _abrirAbono(cxpId, saldo),
                        icon: const Icon(Icons.payments, size: 16),
                        label: const Text('Abonar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _chipCxp('Total', '\$${total.toStringAsFixed(2)}', cs),
                      _chipCxp('Pagado', '\$${pagado.toStringAsFixed(2)}', cs),
                      _chipCxp(
                        'Saldo',
                        '\$${saldo.toStringAsFixed(2)}',
                        cs,
                        destacar: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chipCxp(String etiqueta, String valor, ColorScheme cs,
      {bool destacar = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$etiqueta: ',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: destacar ? cs.error : cs.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Tab "IVA/SENIAT": panel de reportes fiscales descargables (Libro de Ventas,
/// Libro de Compras y Resumen de IVA) para el período seleccionado.
class _SeniatTab extends StatefulWidget {
  const _SeniatTab();

  @override
  State<_SeniatTab> createState() => _SeniatTabState();
}

class _SeniatTabState extends State<_SeniatTab> {
  static const _nombresMeses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  late int _anio;
  late int _mes;
  bool _descargando = false;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _anio = ahora.year;
    _mes = ahora.month;
  }

  String get _tituloPeriodo => '${_nombresMeses[_mes - 1]} $_anio';

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? cs.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Ejecuta una descarga de reporte con indicador de progreso y manejo de error.
  Future<void> _descargar(Future<String?> Function() accion, String okMsg) async {
    if (_descargando) return;
    setState(() => _descargando = true);
    _snack('Preparando reporte fiscal...');
    try {
      final archivo = await accion();
      if (mounted) {
        _snack(archivo == null ? okMsg : 'Reporte descargado: $archivo');
      }
    } catch (e) {
      _snack('Error al generar el reporte: $e', error: true);
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _verResumenIVA() async {
    if (_descargando) return;
    setState(() => _descargando = true);
    try {
      final r = await ApiService.obtenerResumenIVA(anio: _anio, mes: _mes);
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      final ventas = (r['ventas'] as Map<String, dynamic>?) ?? {};
      final compras = (r['compras'] as Map<String, dynamic>?) ?? {};
      Widget fila(String label, double valor, {Color? color}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
                Text(
                  '\$${valor.toStringAsFixed(2)}',
                  style: TextStyle(color: color ?? cs.onSurface, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Resumen de IVA'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Período: $_tituloPeriodo',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                Text('Ventas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                fila('Documentos', _numD(ventas['documentos'])),
                fila('Base Imponible', _numD(ventas['baseImponibleUsd'])),
                fila('IVA Débito', _numD(ventas['ivaDebitoUsd'])),
                fila('IGTF', _numD(ventas['igtfUsd'])),
                const Divider(),
                Text('Compras', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                fila('Documentos', _numD(compras['documentos'])),
                fila('IVA Crédito', _numD(compras['ivaCreditoUsd'])),
                const Divider(),
                fila('IVA a Pagar', _numD(r['ivaAPagarUsd']), color: cs.tertiary),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('Error al obtener el resumen de IVA: $e', error: true);
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Widget _botonAccion({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (color ?? cs.primary).withValues(alpha: 0.15),
          child: Icon(icono, color: color ?? cs.primary),
        ),
        title: Text(titulo, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitulo, style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: _descargando
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
        onTap: _descargando ? null : onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: cs.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reportes Fiscales SENIAT', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: 12),
                // Selector de período (mes / año).
                Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurfaceVariant),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Mes anterior',
                      onPressed: _descargando ? null : _mesAnterior,
                    ),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _tituloPeriodo,
                        isExpanded: true,
                        items: List.generate(12, (i) {
                          final mesAbs = i + 1;
                          return DropdownMenuItem<String>(
                            value: '${_nombresMeses[mesAbs - 1]} $_anio',
                            child: Text(
                              '${_nombresMeses[mesAbs - 1]} $_anio',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }),
                        onChanged: _descargando
                            ? null
                            : (v) {
                                if (v == null) return;
                                _mes = v.split(' ').isNotEmpty
                                    ? _nombresMeses.indexOf(v.split(' ')[0]) + 1
                                    : _mes;
                                setState(() {});
                              },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Mes siguiente',
                      onPressed: _descargando ? null : _mesSiguiente,
                    ),
                    Icon(Icons.arrow_forward_ios, size: 18, color: cs.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _botonAccion(
          icono: Icons.point_of_sale,
          titulo: 'Exportar Libro de Ventas (CSV)',
          subtitulo: 'Facturado en $_tituloPeriodo · IVA e IGTF por documento.',
          onPressed: () => _descargar(
            () => ApiService.exportarLibroVentasCsv(anio: _anio, mes: _mes),
            'Libro de Ventas exportado',
          ),
        ),
        _botonAccion(
          icono: Icons.shopping_cart,
          titulo: 'Exportar Libro de Compras (CSV)',
          subtitulo: 'Notas de recepción de $_tituloPeriodo.',
          onPressed: () => _descargar(
            () => ApiService.exportarLibroComprasCsv(anio: _anio, mes: _mes),
            'Libro de Compras exportado',
          ),
        ),
        _botonAccion(
          icono: Icons.receipt,
          titulo: 'Resumen de IVA (JSON)',
          subtitulo: 'Débito − crédito de $_tituloPeriodo.',
          onPressed: () => _descargar(
            () => ApiService.exportarResumenIvaJson(anio: _anio, mes: _mes),
            'Resumen de IVA descargado',
          ),
          color: cs.tertiary,
        ),
        _botonAccion(
          icono: Icons.visibility,
          titulo: 'Ver Resumen de IVA',
          subtitulo: 'Consulta rápida en pantalla del período.',
          onPressed: _verResumenIVA,
          color: cs.secondary,
        ),
        const SizedBox(height: 8),
        Text(
          'Los archivos CSV incluyen BOM UTF-8 y cumplen RFC-4180 para apertura directa en Excel. Los reportes corresponden a la moneda funcional (USD) y a la tasa BCV histórica.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  void _mesAnterior() {
    setState(() {
      if (_mes == 1) {
        _mes = 12;
        _anio -= 1;
      } else {
        _mes -= 1;
      }
    });
  }

  void _mesSiguiente() {
    setState(() {
      if (_mes == 12) {
        _mes = 1;
        _anio += 1;
      } else {
        _mes += 1;
      }
    });
  }
}
