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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Regresar',
        ),
        title: const Text('8. Finanzas & Caja'),
      ),
      body: Column(
        children: [
          Container(
            color: cs.surfaceContainerLow,
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? const Color(0xFF8B5CF6) : const Color(0xFF6D28D9),
              unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : Colors.grey,
              indicatorColor: isDark ? const Color(0xFF8B5CF6) : const Color(0xFF6D28D9),
              tabs: const [
                Tab(icon: Icon(Icons.account_balance), text: 'Caja'),
                Tab(icon: Icon(Icons.trending_up), text: 'Patrimonio'),
                Tab(icon: Icon(Icons.receipt_long), text: 'Cuentas x Pagar'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patrimonio Operativo Total', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('\$${patrimonio.toStringAsFixed(2)}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Caja Disponible', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                    Text('\$${caja.toStringAsFixed(2)}', style: TextStyle(color: isDark ? Colors.green.shade300 : Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                  const Divider(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Valor del Inventario', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
                    Text('\$${inventario.toStringAsFixed(2)}', style: TextStyle(color: isDark ? Colors.blue.shade300 : Colors.blue, fontWeight: FontWeight.bold, fontSize: 18)),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_cuentas == null) return const Center(child: Text('Error al cargar cuentas'));
    if (_cuentas!.isEmpty) return Center(child: Text('No hay cuentas por pagar', style: TextStyle(color: cs.onSurfaceVariant)));
    return RefreshIndicator(
      onRefresh: _cargarCuentas,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _cuentas!.length,
        itemBuilder: (context, index) {
          final cxp = _cuentas![index];
          final saldo = _numD(cxp['Saldo']);
          final total = _numD(cxp['Monto_Total']);
          final estatus = cxp['Estatus'] ?? 'Pendiente';
          final prov = cxp['proveedores'] as Map<String, dynamic>?;
          return Card(
            color: cs.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: estatus == 'Pendiente' ? Colors.orange.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                child: Icon(estatus == 'Pendiente' ? Icons.pending : Icons.check, color: estatus == 'Pendiente' ? Colors.orange : Colors.green),
              ),
              title: Text('CxP #${cxp['CxP_ID']?.toString() ?? ''} - ${prov?['Razon_Social'] ?? 'Proveedor'}', style: TextStyle(color: cs.onSurface)),
              subtitle: Text('Total: \$${total.toStringAsFixed(2)} - Estatus: $estatus', style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: Text('\$${saldo.toStringAsFixed(2)}', style: TextStyle(color: cs.error, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          );
        },
      ),
    );
  }
}
