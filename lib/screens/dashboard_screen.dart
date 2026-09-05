import 'package:flutter/material.dart';

import 'pos_screen.dart';
import 'inventario_screen.dart';
import 'clientes_screen.dart';
import 'proveedores_screen.dart';
import 'entrada_screen.dart';
import 'facturas_screen.dart';
import 'login_screen.dart';
import 'finanzas_screen.dart';
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
  _ModuloSistema(2, 'Facturas', 'OPERACIÓN', Icons.receipt_long,
      Colors.green, FacturasScreen()),
  _ModuloSistema(3, 'Clientes', 'OPERACIÓN', Icons.people, Colors.teal,
      ClientesScreen()),
  _ModuloSistema(
      4, 'Productos', 'OPERACIÓN', Icons.inventory_2,
      Color(0xFFF59E0B), InventarioScreen()),
  _ModuloSistema(5, 'Entradas', 'OPERACIÓN',
      Icons.add_shopping_cart, Colors.purple, EntradasScreen()),
  _ModuloSistema(6, 'Proveedores', 'ADMINISTRACIÓN', Icons.local_shipping,
      Colors.indigo, ProveedoresScreen()),
  _ModuloSistema(7, 'Métricas Profundas', 'ADMINISTRACIÓN', Icons.insights,
      Colors.deepOrange, null),
  _ModuloSistema(8, 'Finanzas & Caja', 'ADMINISTRACIÓN',
      Icons.account_balance_wallet, Color(0xFF8B5CF6), FinanzasScreen()),
  _ModuloSistema(9, 'Configuración', 'ADMINISTRACIÓN', Icons.settings,
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

  /// Navegación cruzada Dashboard → Facturas: abre el registro de facturas
  /// con el filtro temporal actualmente seleccionado en el dashboard.
  Future<void> _irAFacturas() =>
      _navegar(FacturasScreen(periodoInicial: _periodo));

  Future<void> _navegar(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    // Al regresar de un módulo se recargan las métricas para reflejar cambios.
    _cargarMetricas();
    _cargarSerie();
  }

  /// Caché SWR por clave de período: al alternar tarjetas se sirve el dato
  /// cacheado con latencia cero y se revalida en segundo plano.
  final Map<String, Map<String, dynamic>> _cacheSeries = {};

  /// Selecciona un período: respuesta inmediata desde caché (si existe),
  /// luego revalidación silenciosa contra la API.
  void _seleccionarPeriodo(String p) {
    if (_periodo == p) return;
    final cache = _cacheSeries[p];
    setState(() {
      _periodo = p;
      if (cache != null) {
        _serie = cache;
        _cargandoSerie = false;
        _errorSerie = null;
      }
    });
    _cargarSerie(silencioso: cache != null);
  }

  Future<void> _cargarSerie({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargandoSerie = true;
        _errorSerie = null;
      });
    }
    try {
      final periodoSolicitado = _periodo;
      final data = await ApiService.getSerieFinanciera(periodoSolicitado);
      _cacheSeries[periodoSolicitado] = data;
      if (mounted && _periodo == periodoSolicitado) {
        setState(() { _serie = data; _cargandoSerie = false; });
      }
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
                        ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(4)} Bs/usd'
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
              // Control ÚNICO de período: las tarjetas seleccionan el período
              // (actualizan la serie) y navegan a Facturas con ese filtro.
              _buildTarjetasPeriodo(),
              const SizedBox(height: 12),
              _buildKPIsFinancieros(),
              const SizedBox(height: 12),
              _buildBotonExportar(),
              const SizedBox(height: 20),
              _buildTendenciaVentas(),
              const SizedBox(height: 20),
              _buildTopProductos(),
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

  /// Selector de período (Hoy / Semana / Mes / Año) con separación de
  /// intención: tocar la tarjeta SOLO cambia las métricas (caché SWR,
  /// respuesta inmediata + revalidación en segundo plano); navegar a
  /// Facturas exige el tap explícito en el botón pop-up "Ver Facturas"
  /// que emerge con rebote cuando la tarjeta está activa.
  Widget _buildTarjetasPeriodo() {
    return SizedBox(
      height: 108,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _periodos.map((p) {
          return Expanded(
            child: _TarjetaPeriodo(
              etiqueta: p.$2,
              seleccionada: _periodo == p.$1,
              onSeleccionar: () => _seleccionarPeriodo(p.$1),
              onVerFacturas: () =>
                  _navegar(FacturasScreen(periodoInicial: p.$1)),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Botón de exportación del libro diario (auditoría fiscal local).
  /// Genera un CSV con facturas, desglose fiscal, tasa BCV y métodos de pago
  /// del período activo, lo guarda en Documentos y lo abre con la app asociada.
  Widget _buildBotonExportar() {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.file_download, size: 18),
        label: const Text('Exportar Libro Diario (CSV)'),
        onPressed: _exportarLibroDiario,
      ),
    );
  }

  Future<void> _exportarLibroDiario() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generando libro diario...')),
    );
    try {
      final ruta = await ApiService.exportarLibroDiarioCsv(_periodo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Libro diario exportado: $ruta')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  /// Tarjetas KPI: Layout responsivo con 1-4 columnas según ancho de pantalla.
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
    final margen =
        double.tryParse(_serie?['margenGanancia']?.toString() ?? '') ?? 0.0;
    final valorInv =
        double.tryParse(_serie?['valorInventario']?.toString() ?? '') ?? 0.0;
    final rent = _serie?['rentabilidad'] as Map<String, dynamic>?;
    final pctRent = double.tryParse(rent?['porcentaje']?.toString() ?? '') ?? 0.0;

    final kpis = <_MetricaCard>[
      _MetricaCard(
        icon: Icons.attach_money,
        color: Colors.green,
        titulo: 'Ventas Totales (VES)',
        valor: 'Bs. ${_moneda(ventas['montoTotalBs'])}',
        descripcion:
            '${_num(ventas['cantidadFacturas'])} facturas · equiv. \$${_moneda(ventas['montoTotal'])} USD',
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.trending_up,
        color: margen >= 0 ? Colors.teal : Colors.red,
        titulo: 'Margen de Ganancia',
        valor: '\$${_moneda(margen)}',
        descripcion:
            'Rentabilidad real: ${pctRent.toStringAsFixed(1)}% sobre ventas (Costo = CMP al vender).',
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.receipt_long,
        color: Colors.blueAccent,
        titulo: 'Ticket Promedio',
        valor: 'Bs. ${_moneda(ventas['ticketPromedioBs'])}',
        descripcion:
            '\$${_moneda(ventas['ticketPromedio'])} USD por factura.',
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.warehouse,
        color: Colors.amber.shade800,
        titulo: 'Valor Inventario',
        valor: '\$${_moneda(valorInv)}',
        descripcion: 'Capital invertido: Stock × Costo Promedio.',
        onTap: () => _irAFacturas(),
      ),
    ];

    // Layout responsivo con LayoutBuilder
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        int columnas;
        double aspecto;
        
        if (ancho < 600) {
          columnas = 1; // Móvil
          aspecto = 2.8;
        } else if (ancho < 900) {
          columnas = 2; // Tablet pequeña
          aspecto = 1.8;
        } else if (ancho < 1200) {
          columnas = 3; // Tablet grande
          aspecto = 1.5;
        } else {
          columnas = 4; // Desktop
          aspecto = 1.4;
        }
        
        return GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: aspecto,
          children: kpis,
        );
      },
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
  /// Top 5 productos más vendidos del periodo seleccionado (BI, Fase 6).
  Widget _buildTopProductos() {
    if (_cargandoSerie || _errorSerie != null) return const SizedBox.shrink();

    final top =
        (_serie?['topProductos'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final maxUnidades = top.fold<double>(0, (m, p) {
      final u = (p['unidades'] as num? ?? 0).toDouble();
      return u > m ? u : m;
    });

    // Podio: oro, plata, bronce; el resto en slate.
    const medallas = [
      Color(0xFFF59E0B),
      Color(0xFF94A3B8),
      Color(0xFFB45309),
    ];
    Color colorPosicion(int i) =>
        i < medallas.length ? medallas[i] : const Color(0xFF334155);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.emoji_events, color: Color(0xFFF59E0B), size: 20),
            SizedBox(width: 8),
            Text(
              'Top 5 Productos Más Vendidos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: top.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Sin productos vendidos en el periodo seleccionado.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < top.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: colorPosicion(i),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (top[i]['nombre'] ?? '').toString(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: maxUnidades > 0
                                            ? ((top[i]['unidades'] as num? ??
                                                          0)
                                                      .toDouble() /
                                                  maxUnidades)
                                                .clamp(0.02, 1.0)
                                            : 0.02,
                                        child: Container(
                                          height: 4,
                                          color: colorPosicion(i),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_num(top[i]['unidades'])} und',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '\$${_moneda(top[i]['monto'])}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

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
          Row(
            children: [
              const Text(
                'Alertas de Reposición Crítica',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${alertas.length} críticos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
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


/// Tarjeta de período con botón pop-up "Ver Facturas".
/// Tap en la tarjeta → solo selecciona el período (métricas con caché SWR);
/// tap en el botón flotante → navegación explícita a Facturas. El botón
/// permanece oculto hasta seleccionar la tarjeta y emerge con rebote
/// (Curves.elasticOut); captura su propio gesto (stopPropagation).
class _TarjetaPeriodo extends StatefulWidget {
  final String etiqueta;
  final bool seleccionada;
  final VoidCallback onSeleccionar;
  final VoidCallback onVerFacturas;

  const _TarjetaPeriodo({
    required this.etiqueta,
    required this.seleccionada,
    required this.onSeleccionar,
    required this.onVerFacturas,
  });

  @override
  State<_TarjetaPeriodo> createState() => _TarjetaPeriodoState();
}

class _TarjetaPeriodoState extends State<_TarjetaPeriodo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _escala;
  late final Animation<double> _opacidad;
  late final Animation<Offset> _desplazamiento;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    // Rebote tipo "cartoon pop": entrada elástica, salida rápida y suave.
    _escala = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeIn,
    );
    _opacidad = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    _desplazamiento = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeIn,
    ));
    if (widget.seleccionada) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _TarjetaPeriodo old) {
    super.didUpdateWidget(old);
    if (widget.seleccionada == old.seleccionada) return;
    if (widget.seleccionada) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activo = widget.seleccionada;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Tarjeta seleccionable (solo métricas) ────────────────────
          SizedBox(
            height: 74,
            width: double.infinity,
            child: Card(
              margin: EdgeInsets.zero,
              elevation: activo ? 3 : 1,
              color: activo ? Colors.blueAccent : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: activo ? Colors.blueAccent : const Color(0xFF334155),
                  width: activo ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onSeleccionar,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month,
                        size: 18,
                        color: activo ? Colors.white : Colors.blueAccent,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.etiqueta,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: activo
                              ? Colors.white
                              : const Color(0xFFE2E8F0),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Botón pop-up "Ver Facturas" (rebote elástico) ────────────
          Positioned(
            bottom: -13,
            left: 6,
            right: 6,
            child: IgnorePointer(
              ignoring: !activo,
              child: FadeTransition(
                opacity: _opacidad,
                child: SlideTransition(
                  position: _desplazamiento,
                  child: ScaleTransition(
                    scale: _escala,
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(20),
                      elevation: 6,
                      child: InkWell(
                        onTap: widget.onVerFacturas,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Ver Facturas',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

