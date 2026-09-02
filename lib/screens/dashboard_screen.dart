import 'package:flutter/material.dart';

import 'pos_screen.dart';
import 'inventario_screen.dart';
import 'clientes_screen.dart';
import 'proveedores_screen.dart';
import 'entrada_screen.dart';
import 'facturas_screen.dart';
import 'login_screen.dart';
import '../services/api_service.dart';

import 'configuracion_screen.dart';

String _num(dynamic v) {
  if (v == null) return '0';
  return v.toString();
}

String _moneda(dynamic v) {
  final n = v == null ? 0 : double.tryParse(v.toString()) ?? 0;
  return n.toStringAsFixed(2);
}

/// Fuente única de verdad de los 8 módulos numerados del sistema.
/// El Grid del Dashboard y el Drawer/Sidebar renderizan AMBOS desde esta
/// lista, garantizando que números, nombres, iconos y destinos coincidan
/// siempre con el flujo operativo de la ferretería.
class _ModuloSistema {
  final int numero;
  final String titulo;
  final String seccion; // OPERACIÓN | ADMINISTRACIÓN (agrupación del Drawer)
  final IconData icon;
  final Color color;
  final Widget? pantalla; // null → acción especial (ej. módulo 7: scroll)

  const _ModuloSistema(
    this.numero,
    this.titulo,
    this.seccion,
    this.icon,
    this.color,
    this.pantalla,
  );
}

const List<_ModuloSistema> _modulosSistema = [
  _ModuloSistema(1, 'Ventas / POS', 'OPERACIÓN', Icons.point_of_sale,
      Colors.blueAccent, PosScreen()),
  _ModuloSistema(2, 'Facturas & Ventas', 'OPERACIÓN', Icons.receipt_long,
      Colors.green, FacturasScreen()),
  _ModuloSistema(3, 'Clientes', 'OPERACIÓN', Icons.people, Colors.teal,
      ClientesScreen()),
  _ModuloSistema(
      4, 'Productos & Catálogo', 'OPERACIÓN', Icons.inventory_2,
      Color(0xFFF59E0B), InventarioScreen()),
  _ModuloSistema(5, 'Entradas & Inventario', 'OPERACIÓN',
      Icons.add_shopping_cart, Colors.purple, EntradasScreen()),
  _ModuloSistema(6, 'Proveedores', 'ADMINISTRACIÓN', Icons.local_shipping,
      Colors.indigo, ProveedoresScreen()),
  _ModuloSistema(7, 'Métricas & Reportes', 'ADMINISTRACIÓN', Icons.insights,
      Colors.deepOrange, null), // scroll al panel financiero
  _ModuloSistema(8, 'Configuración', 'ADMINISTRACIÓN', Icons.settings,
      Colors.blueGrey, ConfiguracionScreen()),
];

class _MetricaCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String valor;
  final String descripcion;
  final VoidCallback? onTap;

  const _MetricaCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.valor,
    this.descripcion = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _metricas;
  bool _isLoading = true;
  String? _error;
  double _tasaCambio = 36.50;
  bool _tasaEsBCV = false;

  // ── Serie financiera (Fase 3) ──────────────────────────────────────────────
  String _periodo = 'hoy';
  Map<String, dynamic>? _serie;
  bool _cargandoSerie = true;
  String? _errorSerie;

  static const _periodos = <(String, String)>[
    ('hoy', 'Hoy'),
    ('semana', 'Esta Semana'),
    ('mes', 'Este Mes'),
    ('anio', 'Este Año'),
  ];

  // Controlador de scroll: el módulo 7 (Métricas & Reportes) apunta al panel
  // financiero que vive en este mismo dashboard → hace scroll hacia arriba.
  final ScrollController _scrollController = ScrollController();

  void _irAMetricas() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  void _abrirModulo(_ModuloSistema m) {
    if (m.numero == 7) {
      _irAMetricas();
    } else if (m.pantalla != null) {
      _navegar(m.pantalla!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
    _cargarSerie();
    _cargarTasa();
  }

  Future<void> _cargarTasa() async {
    final tasa = await ApiService.getTasaCambio();
    if (mounted) {
      setState(() {
        _tasaCambio = tasa;
        _tasaEsBCV = ApiService.lastTasaEsBCV;
      });
    }
  }

  Future<void> _cargarMetricas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDashboard();
      if (mounted) {
        setState(() {
          _metricas = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _navegar(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    // Al regresar de un módulo se recargan las métricas para reflejar cambios.
    _cargarMetricas();
    _cargarSerie();
  }

  Future<void> _cargarSerie() async {
    setState(() {
      _cargandoSerie = true;
      _errorSerie = null;
    });
    try {
      final data = await ApiService.getSerieFinanciera(_periodo);
      if (mounted) setState(() { _serie = data; _cargandoSerie = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoSerie = false;
          _errorSerie = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _cerrarSesion() {
    ApiService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Principal - Adrialga'),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tasaEsBCV ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _tasaEsBCV
                        ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(2)} Bs/usd'
                        : 'Tasa BCV: Sin conexión',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _tasaEsBCV
                          ? Colors.blue.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  if (!_tasaEsBCV)
                    const Text(
                      'Usando respaldo',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cargarMetricas();
              _cargarSerie();
              _cargarTasa();
            },
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_cargarMetricas(), _cargarSerie()]);
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEncabezado(),
              const SizedBox(height: 20),
              // ── Sección financiera (Fase 3) ─────────────────────────────
              _buildSelectorPeriodo(),
              const SizedBox(height: 12),
              _buildKPIsFinancieros(),
              const SizedBox(height: 20),
              _buildTendenciaVentas(),
              const SizedBox(height: 20),
              _buildCajaDiaria(),
              const SizedBox(height: 28),
              const Text(
                'Módulos del Sistema',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildSubmenu(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════ SECCIÓN FINANCIERA (Fase 3) ═══════════════════

  /// Selector temporal: Hoy / Esta Semana / Este Mes / Este Año.
  Widget _buildSelectorPeriodo() {
    return Wrap(
      spacing: 8,
      children: _periodos.map((p) {
        final seleccionado = _periodo == p.$1;
        return ChoiceChip(
          label: Text(p.$2),
          selected: seleccionado,
          selectedColor: Colors.blueAccent,
          labelStyle: TextStyle(
            color: seleccionado ? Colors.white : Colors.grey[800],
            fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) {
            setState(() => _periodo = p.$1);
            _cargarSerie();
          },
        );
      }).toList(),
    );
  }

  /// Tarjetas KPI: Ventas Totales, Margen, Ticket Promedio y Valor Inventario.
  Widget _buildKPIsFinancieros() {
    if (_cargandoSerie) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_errorSerie != null) {
      return _panelErrorSerie();
    }

    final ventas = (_serie?['ventas'] as Map<String, dynamic>?) ?? {};
    final margen = (_serie?['margenGanancia'] as num?) ?? 0;
    final valorInv = (_serie?['valorInventario'] as num?) ?? 0;

    final kpis = <Widget>[
      _MetricaCard(
        icon: Icons.attach_money,
        color: Colors.green,
        titulo: 'Ventas Totales (VES)',
        valor: 'Bs. ${_moneda(ventas['montoTotalBs'])}',
        descripcion:
            '${_num(ventas['cantidadFacturas'])} facturas · equiv. \$${_moneda(ventas['montoTotal'])} USD',
        onTap: () => _navegar(const FacturasScreen()),
      ),
      _MetricaCard(
        icon: Icons.trending_up,
        color: margen >= 0 ? Colors.teal : Colors.red,
        titulo: 'Margen de Ganancia',
        valor: '\$${_moneda(margen)}',
        descripcion: '(Precio − Costo histórico) × Cantidad.',
        onTap: () => _navegar(const FacturasScreen()),
      ),
      _MetricaCard(
        icon: Icons.receipt_long,
        color: Colors.blueAccent,
        titulo: 'Ticket Promedio',
        valor: 'Bs. ${_moneda(ventas['ticketPromedioBs'])}',
        descripcion:
            '\$${_moneda(ventas['ticketPromedio'])} USD por factura.',
        onTap: () => _navegar(const FacturasScreen()),
      ),
      _MetricaCard(
        icon: Icons.warehouse,
        color: Colors.amber.shade800,
        titulo: 'Valor Inventario',
        valor: '\$${_moneda(valorInv)}',
        descripcion: 'Capital invertido: Stock × Costo Promedio.',
        onTap: () => _navegar(const InventarioScreen()),
      ),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: kpis,
    );
  }

  Widget _panelErrorSerie() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se pudieron cargar las métricas financieras: $_errorSerie',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: _cargarSerie,
            child: const Text(
              'Reintentar',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tendencia de ventas: barras horizontales nativas (sin dependencias).
  Widget _buildTendenciaVentas() {
    final tituloSerie = switch (_periodo) {
      'hoy' => 'Ventas por Hora (Hoy)',
      'semana' => 'Ventas por Día (Últimos 7 días)',
      'mes' => 'Ventas por Día (Mes Actual)',
      _ => 'Ventas por Mes (Año Actual)',
    };

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _cargandoSerie
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tituloSerie,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _serieBarras(),
                ],
              ),
      ),
    );
  }

  Widget _serieBarras() {
    final serie = (_serie?['serie'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    if (serie.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Sin ventas registradas en el periodo seleccionado.',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }
    final maxMonto = serie.fold<double>(
      0,
      (max, f) {
        final m = (f['montoBs'] as num? ?? f['monto'] as num? ?? 0).toDouble();
        return m > max ? m : max;
      },
    );

    return Column(
      children: serie.map((f) {
        final montoBs = (f['montoBs'] as num? ?? 0).toDouble();
        final factor = maxMonto > 0 ? montoBs / maxMonto : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  '${f['etiqueta']}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: factor == 0 ? 0.02 : factor,
                    child: Container(height: 16, color: Colors.blueAccent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(
                  'Bs. ${_moneda(montoBs)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Desglose de caja diaria por método de pago + alertas de stock.
  Widget _buildCajaDiaria() {
    final caja = (_serie?['cajaDiaria'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final alertas = (_serie?['alertasStock'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    IconData iconoMetodo(String m) {
      final s = m.toLowerCase();
      if (s.contains('efectivo usd')) return Icons.payments;
      if (s.contains('pago')) return Icons.phone_android;
      if (s.contains('punto')) return Icons.credit_card;
      return Icons.money;
    }

    String prefijoMetodo(String m) {
      final s = m.toUpperCase();
      return (s.contains('VES') || s.contains('MOVIL') || s.contains('VENTA'))
          ? 'Bs. '
          : '\$';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Caja del Día (por método de pago)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: caja.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Sin pagos registrados hoy.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : Column(
                    children: caja
                        .map(
                          (c) => ListTile(
                            dense: true,
                            leading: Icon(
                              iconoMetodo((c['metodo'] ?? '').toString()),
                              color: Colors.blueAccent,
                            ),
                            title: Text(
                              (c['metodo'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Text(
                              '${prefijoMetodo((c['metodo'] ?? '').toString())}${_moneda(c['monto'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
        if (alertas.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Alertas de Stock Bajo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 2,
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: alertas
                    .take(5)
                    .map(
                      (p) => ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.warning_amber,
                          color: Colors.red.shade700,
                        ),
                        title: Text(
                          (p['Nombre'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Stock: ${p['Stock_Actual']} (Mín: ${p['Stock_Minimo']})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => _navegar(const EntradasScreen()),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEncabezado() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront, color: Colors.white, size: 34),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Ferretería Adrialga C.A.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Sistema de gestión de ventas e inventario',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }



  Widget _buildSubmenu() {
    return GridView.count(
      crossAxisCount: _columnasSubmenu(),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: _modulosSistema
          .map((m) => _tarjetaModulo(m, badge: _badgeForModule(m)))
          .toList(),
    );
  }

  /// Tarjeta numerada del módulo (misma fuente que el Drawer).
  /// Muestra un badge contextual debajo del título cuando hay datos disponibles.
  Widget _tarjetaModulo(_ModuloSistema m, {Widget? badge}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirModulo(m),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              clipBehavior: Clip.none,
              children: [
                Icon(m.icon, size: 30, color: m.color),
                Positioned(
                  right: -14,
                  top: -10,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: m.color,
                    child: Text(
                      '${m.numero}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                m.titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 6),
              badge,
            ],
          ],
        ),
      ),
    );
  }

  /// Devuelve un badge contextual por módulo basado en las métricas cargadas.
  /// Retona null si no hay datos o el módulo no tiene badge asignado.
  Widget? _badgeForModule(_ModuloSistema m) {
    if (_isLoading || _error != null || _metricas == null) return null;
    final resumen = (_metricas?['resumen'] as Map<String, dynamic>?) ?? {};
    final alertas = (_metricas?['alertas'] as Map<String, dynamic>?) ?? {};

    switch (m.numero) {
      case 4: // Productos & Catálogo
        return _badge('${resumen['totalProductos'] ?? 0} ítems', Colors.blue);
      case 3: // Clientes
        return _badge('${resumen['totalClientes'] ?? 0} reg.', Colors.teal);
      case 6: // Proveedores
        return _badge('${resumen['totalProveedores'] ?? 0} reg.', Colors.indigo);
      case 2: // Facturas & Ventas
        return _badge('${resumen['totalFacturas'] ?? 0} emitidas', Colors.green);
      case 5: // Entradas & Inventario → alerta stock bajo
        final stockBajo = (alertas['conteoStockBajo'] ?? 0) as int;
        return stockBajo > 0 ? _badgeAlert(stockBajo) : null;
      default:
        return null;
    }
  }

  /// Badge neutro con texto y color de acento.
  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Badge de alerta rojo para stock bajo.
  Widget _badgeAlert(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count bajo stock',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  int _columnasSubmenu() {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho >= 1200) return 4;
    if (ancho >= 800) return 3;
    if (ancho >= 600) return 2;
    return 2;
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueAccent),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.storefront, color: Colors.white, size: 48),
                SizedBox(height: 8),
                Text(
                  'Adrialga',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Flujo operativo del negocio',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          // Ítems generados desde la MISMA fuente que el Grid del Dashboard:
          // números, títulos, iconos y destinos idénticos por construcción.
          for (final seccion in const ['OPERACIÓN', 'ADMINISTRACIÓN']) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                seccion,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            ..._modulosSistema
                .where((m) => m.seccion == seccion)
                .map(_drawerItem),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Cerrar sesión',
              style: TextStyle(color: Colors.red),
            ),
            onTap: _cerrarSesion,
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(_ModuloSistema m) {
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: m.color.withValues(alpha: 0.15),
        child: Text(
          '${m.numero}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: m.color,
          ),
        ),
      ),
      title: Text(
        m.titulo,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onTap: () {
        Navigator.pop(context); // cierra el drawer
        _abrirModulo(m);
      },
    );
  }
}
