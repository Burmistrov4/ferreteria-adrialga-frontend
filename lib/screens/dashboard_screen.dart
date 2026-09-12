import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'pos_screen.dart';
import 'inventario_screen.dart';
import 'clientes_screen.dart';
import 'proveedores_screen.dart';
import 'entrada_screen.dart';
import 'facturas_screen.dart';
import 'login_screen.dart';
import 'finanzas_screen.dart';
import '../services/api_service.dart';
import '../services/preferences_service.dart';
import '../services/shortcut_service.dart';
import '../widgets/walkthrough_overlay.dart';

import 'configuracion_screen.dart';

String _num(dynamic v) {
  if (v == null) return '0';
  return v.toString();
}

String _moneda(dynamic v) {
  final n = v == null ? 0 : double.tryParse(v.toString()) ?? 0;
  return n.toStringAsFixed(2);
}

double _parseNum(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

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

/// Paleta de módulos basada en tokens de ColorScheme para consistencia
/// light/dark automática. Se resuelve en tiempo de build().
List<_ModuloSistema> _modulosSistema(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    _ModuloSistema(1, 'Ventas / POS', 'OPERACIÓN', Icons.point_of_sale,
        scheme.primary, PosScreen()),
    _ModuloSistema(2, 'Facturas', 'OPERACIÓN', Icons.receipt_long,
        scheme.secondary, FacturasScreen()),
    _ModuloSistema(3, 'Clientes', 'OPERACIÓN', Icons.people,
        scheme.tertiary, ClientesScreen()),
    _ModuloSistema(4, 'Productos', 'OPERACIÓN', Icons.inventory_2,
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), InventarioScreen()), // Amber
    _ModuloSistema(5, 'Entradas', 'OPERACIÓN',
        Icons.add_shopping_cart, isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED), EntradasScreen()), // Violet
    _ModuloSistema(6, 'Proveedores', 'ADMINISTRACIÓN', Icons.local_shipping,
        isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA), ProveedoresScreen()), // Indigo
    // Módulo 7: las métricas profundas viven en el propio Dashboard —
    // _abrirModulo hace scroll a esa sección (ver _irAMetricas).
    _ModuloSistema(7, 'Métricas Profundas', 'ADMINISTRACIÓN', Icons.insights,
        isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C), null), // Deep Orange
    _ModuloSistema(8, 'Finanzas & Caja', 'ADMINISTRACIÓN',
        Icons.account_balance_wallet, isDark ? const Color(0xFFC084FC) : const Color(0xFF6D28D9), FinanzasScreen()), // Purple
    _ModuloSistema(9, 'Configuración', 'ADMINISTRACIÓN', Icons.settings,
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569), ConfiguracionScreen()), // Slate
  ];
}

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
    final colorScheme = Theme.of(context).colorScheme;
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
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
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
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
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
  /// Cuando el Dashboard vive dentro del AppShell, el tap en una tarjeta de
  /// módulo cambia de pestaña en el shell (transición fluida con estado
  /// preservado). Si es null (uso aislado), se hace push de la pantalla.
  final ValueChanged<int>? onNavegarModulo;

  const DashboardScreen({super.key, this.onNavegarModulo});

  /// Índice de la pestaña del AppShell que corresponde a cada módulo.
  static const _indiceShellDeModulo = <int, int>{
    1: 1, // Ventas / POS
    2: 2, // Facturas
    3: 3, // Clientes
    4: 4, // Productos
    5: 5, // Entradas (Compras)
    6: 6, // Proveedores
    8: 7, // Finanzas & Caja
    9: 8, // Configuración (Ajustes)
  };

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
    } else if (widget.onNavegarModulo != null &&
        DashboardScreen._indiceShellDeModulo.containsKey(m.numero)) {
      // Navegación fluida dentro del AppShell: cambio de pestaña sin push.
      widget.onNavegarModulo!(DashboardScreen._indiceShellDeModulo[m.numero]!);
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
    ShortcutService.setModule('dashboard');
    _cargarMetricas();
    _cargarSerie();
    _cargarTasa();
    // Onboarding de primer uso: tras el login, si el cajero aún no lo completó,
    // se muestra el tutorial guiado de 5 pasos (solo en la primera ejecución).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluarWalkthroughInicial();
    });
  }

  /// Muestra el walkthrough de primer uso si `has_completed_onboarding`
  /// es falso. Al finalizar/omitir se persiste el estado para no repetirlo.
  Future<void> _evaluarWalkthroughInicial() async {
    final hecho = await PreferencesService.getOnboardingDone();
    if (!mounted || hecho) return;
    WalkthroughOverlay.mostrar(
      context,
      pasos: walkthroughCajero(),
      onCompletado: () => PreferencesService.setOnboardingDone(true),
      onOmitido: () => PreferencesService.setOnboardingDone(true),
    );
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control'),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tasaEsBCV
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh,
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
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (!_tasaEsBCV)
                    Text(
                      'Usando respaldo',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
              _buildInsightsPanel(),
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

  // ═══════════════ MOTOR DE INSIGHTS INTELIGENTES (Fase 8) ═══════════════
  // Reglas de negocio que derivan recomendaciones accionables de la serie
  // financiera ya cargada (cero llamadas extra al backend).

  /// Genera la lista de insights del período activo, ordenada por prioridad.
  List<({IconData icon, Color color, String titulo, String mensaje, VoidCallback? accion, String? accionTexto})>
      _generarInsights() {
    final insights = <({IconData icon, Color color, String titulo, String mensaje, VoidCallback? accion, String? accionTexto})>[];
    final s = _serie;
    if (s == null) return insights;

    final ventas = (s['ventas'] as Map<String, dynamic>?) ?? const {};
    final rent = (s['rentabilidad'] as Map<String, dynamic>?) ?? const {};
    final serie = (s['serie'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final caja = (s['cajaDiaria'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final alertas = (s['alertasStock'] as List<dynamic>?) ?? const [];

    // 1) Margen de ganancia: umbral ferretería sano ≈ 25%.
    final pctMargen = _parseNum(rent['porcentaje']);
    final margenUsd = _parseNum(rent['margenUsd']);
    if (_parseNum(ventas['montoTotal']) > 0) {
      if (pctMargen < 15) {
        insights.add((
          icon: Icons.trending_down,
          color: Colors.redAccent,
          titulo: 'Margen bajo (${pctMargen.toStringAsFixed(1)}%)',
          mensaje:
              'Ganancia de \$${_moneda(margenUsd)} sobre \$${_moneda(ventas['montoTotal'])} en ventas. Revisa precios de costo y márgenes por producto antes de reponer inventario.',
          accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
        ));
      } else if (pctMargen >= 30) {
        insights.add((
          icon: Icons.trending_up,
          color: Colors.green,
          titulo: 'Excelente margen (${pctMargen.toStringAsFixed(1)}%)',
          mensaje:
              'La rentabilidad del período supera el 30%. Momento ideal para negociar volumen con proveedores o invertir en stock de alta rotación.',
          accion: () => _navegar(FacturasScreen(periodoInicial: _periodo)), accionTexto: 'Ver facturas',
        ));
      } else {
        insights.add((
          icon: Icons.percent,
          color: Colors.blueAccent,
          titulo: 'Margen saludable (${pctMargen.toStringAsFixed(1)}%)',
          mensaje:
              'Ganancia de \$${_moneda(margenUsd)} en el período. Un empuje del 5% en el ticket promedio sumaría \$${_moneda(margenUsd * 0.05 / (pctMargen / 100))} adicionales.',
          accion: () => _navegar(FacturasScreen(periodoInicial: _periodo)), accionTexto: 'Ver facturas',
        ));
      }
    }

    // 2) Tendencia: compara los dos últimos tramos de la serie.
    if (serie.length >= 2) {
      final previo = _parseNum(serie[serie.length - 2]['montoBs']);
      final actual = _parseNum(serie[serie.length - 1]['montoBs']);
      if (previo > 0) {
        final variacion = ((actual - previo) / previo) * 100;
        if (variacion <= -15) {
          insights.add((
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            titulo: 'Ventas cayendo (${variacion.toStringAsFixed(0)}%)',
            mensaje:
                'El último tramo cerró en Bs. ${_moneda(actual)} vs Bs. ${_moneda(previo)} del anterior. Considera promociones o verificar disponibilidad de los productos más vendidos.',
            accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
          ));
        } else if (variacion >= 15) {
          insights.add((
            icon: Icons.rocket_launch,
            color: Colors.green,
            titulo: 'Ventas al alza (+${variacion.toStringAsFixed(0)}%)',
            mensaje:
                'Bs. ${_moneda(actual)} en el último tramo (+${variacion.toStringAsFixed(0)}%). Asegura stock del Top 5 para no perder la racha.',
            accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
          ));
        }
      }
    }

    // 3) Mejor franja: el tramo con mayores ventas (personal/reposición).
    if (serie.length >= 3) {
      Map<String, dynamic> mejor = serie.first;
      for (final f in serie) {
        if (_parseNum(f['montoBs']) > _parseNum(mejor['montoBs'])) mejor = f;
      }
      if (_parseNum(mejor['montoBs']) > 0) {
        insights.add((
          icon: Icons.schedule,
          color: Colors.deepPurple,
          titulo: 'Mejor momento: ${mejor['etiqueta']}',
          mensaje:
              'Concentró Bs. ${_moneda(mejor['montoBs'])}. Prioriza cajero y reposición de mercancía en esa franja.',
          accion: null, accionTexto: null,
        ));
      }
    }

    // 4) Stock crítico: productos en o bajo el mínimo.
    final conteoAlertas = alertas.length;
    if (conteoAlertas > 0) {
      final primero = (alertas.first as Map).cast<String, dynamic>();
      insights.add((
        icon: Icons.inventory,
        color: Colors.amber.shade800,
        titulo: '$conteoAlertas producto(s) en stock mínimo',
        mensaje:
            '"${primero['Nombre']}" está al límite. Genera la nota de entrada antes de que la venta lo agote.',
        accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
      ));
    }

    // 5) Concentración de cobros: método dominante del período.
    if (caja.isNotEmpty) {
      final total = caja.fold<double>(0, (t, c) => t + _parseNum(c['monto']));
      if (total > 0) {
        final dominante = caja.first; // ya viene ordenado desc por el backend
        final pct = _parseNum(dominante['monto']) / total * 100;
        if (pct >= 60) {
          insights.add((
            icon: Icons.account_balance_wallet,
            color: const Color(0xFF8B5CF6),
            titulo: '${dominante['metodo']}: ${pct.toStringAsFixed(0)}% de los cobros',
            mensaje:
                'Fuerte concentración en un solo método. Verifica que el flujo de caja físico cubra los egresos en efectivo del día.',
            accion: () => _navegar(FinanzasScreen()), accionTexto: 'Ver caja',
          ));
        }
      }
    }

    // 6) Asistente de Negocio (analítica de 30 días del backend).
    final asist = (s['asistente'] as Map<String, dynamic>?) ?? const {};
    final muerto =
        (asist['inventarioMuerto'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final margenLista =
        (asist['alertasMargen'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final rot =
        (asist['rotacion'] as Map<String, dynamic>?) ?? const {};
    final mayor =
        (rot['mayorRotacion'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    if (muerto.isNotEmpty) {
      final valMuerto = muerto.fold<double>(
          0, (t, p) => t + _parseNum(p['valorDolares']));
      final p1 = muerto.first;
      insights.add((
        icon: Icons.dangerous,
        color: Theme.of(context).colorScheme.error,
        titulo: 'Inventario muerto: ${muerto.length} producto(s)',
        mensaje:
            '\$${_moneda(valMuerto)} estancados sin ventas en 30 días. Ej: "${p1['nombre']}" (${p1['stock']} uds). Promociona o descuenta por lote.',
        accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
      ));
    }

    for (final p in margenLista.take(3)) {
      final pct = _parseNum(p['margenPct']);
      final perdida = pct < 0;
      insights.add((
        icon: Icons.trending_down,
        color: perdida
            ? Theme.of(context).colorScheme.error
            : Colors.orange,
        titulo: 'Margen ${perdida ? 'a pérdida' : 'bajo'} · ${p['nombre']}',
        mensaje:
            '${pct.toStringAsFixed(1)}% (precio \$${_moneda(p['precioDolar'])} vs costo \$${_moneda(p['costoDolar'])}). Reevalúa costo de compra o precio.',
        accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
      ));
    }

    if (mayor.isNotEmpty) {
      final t = mayor.first;
      insights.add((
        icon: Icons.local_fire_department,
        color: Colors.green,
        titulo: 'Alta rotación · ${t['nombre']}',
        mensaje:
            'Índice ${t['indice']} (${t['unidades']} uds en 30 días vs ${t['stock']} en stock). Garantiza reposición.',
        accion: () => _navegar(InventarioScreen()), accionTexto: 'Revisar producto',
      ));
    }

    // 7) Predicción de quiebre de stock: días restantes estimados a partir
    //    del ritmo de venta de los últimos 30 días (rotación del asistente).
    for (final p in mayor.take(5)) {
      final stock = _parseNum(p['stock']);
      final vendidas = _parseNum(p['unidades']);
      if (vendidas <= 0) continue;
      final dias = (stock / (vendidas / 30.0)).floor();
      if (dias <= 7) {
        insights.add((
          icon: Icons.hourglass_bottom_rounded,
          color: dias <= 3
              ? Theme.of(context).colorScheme.error
              : Colors.orange,
          titulo: '${p['nombre']}: se agota en ~$dias día(s)',
          mensaje:
              'Quedan ${stock.toStringAsFixed(0)} uds y el ritmo de venta es de ${vendidas.toStringAsFixed(0)} uds cada 30 días. Haz la compra hoy para no perder ventas.',
          accion: () => _navegar(EntradasScreen(
              productoInicialId: (p['id'] as num?)?.toInt())),
          accionTexto: 'Registrar compra',
        ));
      }
    }

    return insights;
  }

  /// Panel "Asistente de Negocio": recomendaciones accionables del período.
  Widget _buildInsightsPanel() {
    if (_cargandoSerie) return const SizedBox.shrink();
    final insights = _generarInsights();
    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Asistente de Negocio',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...insights.take(7).map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                elevation: 1,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: i.accion,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(i.icon, color: i.color, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.titulo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                i.mensaje,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              // Acción Rápida: botón etiquetado dentro de la
                              // alerta (CIERRE DE CICLO: ver → decidir → actuar).
                              if (i.accion != null && i.accionTexto != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                          minHeight: 48),
                                      child: FilledButton.tonalIcon(
                                        onPressed: i.accion,
                                        icon: Icon(i.icon, size: 16),
                                        label: Text(
                                          i.accionTexto!,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (i.accion != null)
                          Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _panelErrorSerie() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se pudieron cargar las métricas financieras: $_errorSerie',
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
          GestureDetector(
            onTap: _cargarSerie,
            child: Text(
              'Reintentar',
              style: TextStyle(
                color: colorScheme.primary,
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
    final colorScheme = Theme.of(context).colorScheme;
    final serie = (_serie?['serie'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    if (serie.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Sin ventas registradas en el periodo seleccionado.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }

    // Normalización de montos: los valores de la API llegan como num/String.
    final montos = serie
        .map((f) => (f['montoBs'] as num? ?? f['monto'] as num? ?? 0).toDouble())
        .toList();
    final maxMonto = montos.fold<double>(0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxMonto > 0 ? maxMonto * 1.15 : 1,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colorScheme.inverseSurface,
              getTooltipItem: (group, gIdx, rod, rIdx) =>
                  BarTooltipItem(
                'Bs. ${_moneda(montos[gIdx])}\n',
                TextStyle(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: '${serie[gIdx]['etiqueta']}',
                    style: TextStyle(
                      color: colorScheme.onInverseSurface,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Text(
                'Bs.',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: maxMonto > 0
                    ? (maxMonto / 3).toDouble().clamp(1, double.infinity)
                    : 1,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    _moneda(v),
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= serie.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${serie[i]['etiqueta']}',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxMonto > 0
                ? (maxMonto / 3).toDouble().clamp(1, double.infinity)
                : 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          barGroups: List.generate(serie.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: montos[i],
                  color: colorScheme.primary,
                  width: _anchoBarra(),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// Ancho de barra responsivo: móvil angosto usa barras delgadas para que
  /// 24 tramos horarios quepan sin amontonarse; pantallas anchas engordan.
  double _anchoBarra() {
    final ancho = MediaQuery.of(context).size.width;
    final n = ((_serie?['serie'] as List<dynamic>?)?.length ?? 8);
    if (ancho < 600) return 8;
    if (ancho < 1024) return 14;
    // Escritorio: escala con la densidad de tramos de la serie.
    return n > 12 ? 16 : 22;
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
                ? _estadoVacio(
                    icono: Icons.emoji_events_outlined,
                    titulo: 'Aún no hay ventas registradas',
                    mensaje:
                        'Cuando realices tu primera venta, aquí aparecerán tus productos estrella.',
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
                ? _estadoVacio(
                    icono: Icons.point_of_sale_outlined,
                    titulo: 'Sin ventas de hoy todavía',
                    mensaje:
                        'Abre una venta desde “Vender” y los cobros aparecerán aquí separados por método de pago.',
                    accionTexto: 'Vender ahora',
                    onAccion: () => widget.onNavegarModulo != null
                        ? widget.onNavegarModulo!(1)
                        : _navegar(PosScreen()),
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
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${alertas.length} críticos',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
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
            color: Theme.of(context).colorScheme.errorContainer,
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
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          (p['Nombre'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        subtitle: Text(
                          'Stock: ${p['Stock_Actual']} (Mín: ${p['Stock_Minimo']})',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        // Banner accionable → Entradas con precarga de los
                        // productos con quiebre (producto tocado preseleccionado).
                        onTap: () {
                          final ids = alertas
                              .map<int>((a) =>
                                  (a['Producto_ID'] as num?)?.toInt() ?? 0)
                              .where((id) => id != 0)
                              .toList();
                          _navegar(EntradasScreen(
                            productoInicialId:
                                (p['Producto_ID'] as num?)?.toInt(),
                            idsBajoStock: ids,
                          ));
                        },
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

  /// Empty State ilustrado y accionable: icono grande tenue, título
  /// amigable, mensaje orientativo y CTA opcional (área táctil ≥ 48 dp).
  Widget _estadoVacio({
    required IconData icono,
    required String titulo,
    required String mensaje,
    String? accionTexto,
    VoidCallback? onAccion,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 44, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          if (accionTexto != null && onAccion != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.tonalIcon(
                onPressed: onAccion,
                icon: Icon(icono, size: 18),
                label: Text(accionTexto),
              ),
            ),
          ],
        ],
      ),
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
            children: [
              const Text(
                'Ferretería Adrialga C.A.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Sistema de gestión de ventas e inventario',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
      children: _modulosSistema(context)
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

// Navegación por pestañas gestionada por el AppShell (Drawer eliminado).
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
    final colorScheme = Theme.of(context).colorScheme;
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
              color: activo ? colorScheme.primary : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: activo
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
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
                        color: activo
                            ? colorScheme.onPrimary
                            : colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.etiqueta,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: activo
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
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
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      elevation: 6,
                      child: InkWell(
                        onTap: widget.onVerFacturas,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
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
                                color: colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Ver Facturas',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
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

