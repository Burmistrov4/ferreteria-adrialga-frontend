import 'package:flutter/material.dart';

import '../widgets/bi_serie_chart.dart';

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
import '../services/socket_service.dart';
import '../widgets/walkthrough_overlay.dart';
import '../utils/responsive.dart';

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
    _ModuloSistema(
      1,
      'Ventas / POS',
      'OPERACIÓN',
      Icons.point_of_sale,
      scheme.primary,
      PosScreen(),
    ),
    _ModuloSistema(
      2,
      'Facturas',
      'OPERACIÓN',
      Icons.receipt_long,
      scheme.secondary,
      FacturasScreen(),
    ),
    _ModuloSistema(
      3,
      'Clientes',
      'OPERACIÓN',
      Icons.people,
      scheme.tertiary,
      ClientesScreen(),
    ),
    _ModuloSistema(
      4,
      'Productos',
      'OPERACIÓN',
      Icons.inventory_2,
      isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
      InventarioScreen(),
    ), // Amber
    _ModuloSistema(
      5,
      'Entradas',
      'OPERACIÓN',
      Icons.add_shopping_cart,
      isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
      EntradasScreen(),
    ), // Violet
    _ModuloSistema(
      6,
      'Proveedores',
      'ADMINISTRACIÓN',
      Icons.local_shipping,
      isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA),
      ProveedoresScreen(),
    ), // Indigo
    // Módulo 7: las métricas profundas viven en el propio Dashboard —
    // _abrirModulo hace scroll a esa sección (ver _irAMetricas).
    _ModuloSistema(
      7,
      'Métricas Profundas',
      'ADMINISTRACIÓN',
      Icons.insights,
      isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
      null,
    ), // Deep Orange
    _ModuloSistema(
      8,
      'Finanzas & Caja',
      'ADMINISTRACIÓN',
      Icons.account_balance_wallet,
      isDark ? const Color(0xFFC084FC) : const Color(0xFF6D28D9),
      FinanzasScreen(),
    ), // Purple
    _ModuloSistema(
      9,
      'Configuración',
      'ADMINISTRACIÓN',
      Icons.settings,
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      ConfiguracionScreen(),
    ), // Slate
  ];
}

class _MetricaCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String valor;
  final String descripcion;
  final VoidCallback? onTap;

  /// Variación % vs. período anterior (null = sin base de comparación).
  final double? deltaPct;

  const _MetricaCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.valor,
    this.descripcion = '',
    this.onTap,
    this.deltaPct,
  });

  /// Insignia de variación vs período anterior: sube = verde, cae = rojo.
  Widget _badgeDelta() {
    final pct = deltaPct!;
    final sube = pct >= 0;
    final color = sube ? Colors.green.shade700 : Colors.red.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          sube ? Icons.arrow_upward : Icons.arrow_downward,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${sube ? '+' : ''}${pct.toStringAsFixed(1)}% vs período previo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // LayoutBuilder + FittedBox(scaleDown): el contenido se dibuja a su
        // tamaño natural y SOLO se encoge cuando la celda del grid queda más
        // baja que el contenido (móvil angosto / aspect ratio forzoso).
        // Elimina el "BOTTOM OVERFLOWED" sin fijar alturas manuales.
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 14 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 10),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (deltaPct != null) ...[
                const SizedBox(height: 4),
                _badgeDelta(),
              ],
              const SizedBox(height: 2),
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
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

  void _alRecibirDbUpdate(String modulo) {
    if (!mounted) return;
    // El dashboard también muestra conteos de clientes/proveedores, alertas de
    // stock y compras. Esos datos cambian desde otros terminales sin que haya
    // necesariamente una venta nueva.
    const modulosQueAfectanDashboard = {
      'ventas',
      'inventario',
      'clientes',
      'proveedores',
      'caja',
      'finanzas',
      '__reconexion__',
    };
    if (!modulosQueAfectanDashboard.contains(modulo)) return;
    _cargarMetricas(silencioso: true);
    _cargarSerie(silencioso: true);
  }

  @override
  void dispose() {
    SocketService.offDbUpdateModulo(_alRecibirDbUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SocketService.onDbUpdateModulo(_alRecibirDbUpdate);
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

  Future<void> _cargarMetricas({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
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
        setState(() {
          _serie = data;
          _cargandoSerie = false;
        });
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

  Widget _buildTasaCompacta(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _tasaEsBCV ? cs.primaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        _tasaEsBCV
            ? 'BCV ${_tasaCambio.toStringAsFixed(4)}'
            : 'BCV sin conexión',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: _tasaEsBCV ? cs.onPrimaryContainer : cs.onSurface,
        ),
      ),
    );
  }

  void _mostrarTasa(BuildContext context, ColorScheme cs) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tasa de cambio'),
        content: Text(
          _tasaEsBCV ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(4)} Bs/USD' : 'No hay conexión con BCV. Se está utilizando el respaldo disponible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control'),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 600)
            _buildTasaCompacta(colorScheme),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cargarMetricas();
              _cargarSerie();
              _cargarTasa();
            },
            tooltip: 'Actualizar',
          ),
          if (MediaQuery.sizeOf(context).width >= 600)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _cerrarSesion,
              tooltip: 'Cerrar sesión',
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'tasa') _mostrarTasa(context, colorScheme);
                if (value == 'logout') _cerrarSesion();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'tasa', child: Text('Ver tasa BCV')),
                PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_cargarMetricas(), _cargarSerie()]);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            return SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: AdrialgaResponsive.contentMaxWidth(ancho),
                  ),
                  child: Padding(
                    padding: AdrialgaResponsive.pageInsets(ancho),
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
                        _buildResponsivePair(
                          _buildInsightsPanel(),
                          _buildTopCajeros(),
                        ),
                        const SizedBox(height: 20),
                        _buildResponsivePair(
                          _buildTopProductos(),
                          _buildCajaDiaria(),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Módulos del Sistema',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSubmenu(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final columnas = ancho < 600
            ? 2
            : ancho < 1000
            ? 2
            : 4;
        final relacion = ancho < 600
            ? 2.35
            : ancho < 1000
            ? 2.8
            : 3.1;
        return GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: relacion,
          children: _periodos.map((p) {
            return _TarjetaPeriodo(
              etiqueta: p.$2,
              seleccionada: _periodo == p.$1,
              onSeleccionar: () => _seleccionarPeriodo(p.$1),
              onVerFacturas: () =>
                  _navegar(FacturasScreen(periodoInicial: p.$1)),
            );
          }).toList(),
        );
      },
    );
  }

  /// Botón de exportación del libro diario (auditoría fiscal local).
  /// Genera un CSV con facturas, desglose fiscal, tasa BCV y métodos de pago
  /// del período activo, lo guarda en Documentos y lo abre con la app asociada.
  Widget _buildBotonExportar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 600;
        return Align(
          alignment: compacto ? Alignment.centerLeft : Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_download, size: 18),
            label: Text(
              compacto ? 'Exportar CSV' : 'Exportar Libro Diario (CSV)',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _exportarLibroDiario,
          ),
        );
      },
    );
  }

  Future<void> _exportarLibroDiario() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generando libro diario...')));
    try {
      final ruta = await ApiService.exportarLibroDiarioCsv(_periodo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Libro diario exportado: $ruta')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
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
    final pctRent =
        double.tryParse(rent?['porcentaje']?.toString() ?? '') ?? 0.0;
    // Comparativa vs período anterior (deltas % para las insignias de KPI).
    final comp = (_serie?['comparativa'] as Map<String, dynamic>?) ?? {};
    double? delta(Object? v) =>
        v == null ? null : double.tryParse(v.toString());

    final kpis = <_MetricaCard>[
      _MetricaCard(
        icon: Icons.attach_money,
        color: Colors.green,
        titulo: 'Ventas Totales (VES)',
        valor: 'Bs. ${_moneda(ventas['montoTotalBs'])}',
        descripcion:
            '${_num(ventas['cantidadFacturas'])} facturas · equiv. \$${_moneda(ventas['montoTotal'])} USD',
        deltaPct: delta(comp['deltaVentasPct']),
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.trending_up,
        color: margen >= 0 ? Colors.teal : Colors.red,
        titulo: 'Margen de Ganancia',
        valor: '\$${_moneda(margen)}',
        descripcion:
            'Margen bruto estimado: ${pctRent.toStringAsFixed(1)}% sobre ventas (costo histórico al vender; no es utilidad neta).',
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.receipt_long,
        color: Colors.blueAccent,
        titulo: 'Ticket Promedio',
        valor: 'Bs. ${_moneda(ventas['ticketPromedioBs'])}',
        descripcion: '\$${_moneda(ventas['ticketPromedio'])} USD por factura.',
        deltaPct: delta(comp['deltaTicketPct']),
        onTap: () => _irAFacturas(),
      ),
      _MetricaCard(
        icon: Icons.warehouse,
        color: Colors.amber.shade800,
        titulo: 'Valor Inventario',
        valor: '\$${_moneda(valorInv)}',
        descripcion: 'Capital invertido: Stock × Costo Promedio.',
        onTap: () => _navegar(InventarioScreen()),
      ),
    ];

    // Layout responsivo con LayoutBuilder
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        int columnas;
        double aspecto;

        if (ancho < 600) {
          columnas = 1; // 375 dp: KPI completo, fácil de escanear.
          aspecto = 3.05;
        } else if (ancho < 900) {
          columnas = 2; // 768 dp: dos tarjetas sin comprimir el contenido.
          aspecto = 1.9;
        } else if (ancho < 1200) {
          columnas = 3; // 1024 dp: aprovecha el ancho sin miniaturizar.
          aspecto = 1.65;
        } else {
          columnas = 4; // 1280/1440+: lectura de escritorio.
          aspecto = 1.55;
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

  Widget _buildResponsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AdrialgaResponsive.tablet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(
                height: AdrialgaResponsive.sectionGap(constraints.maxWidth),
              ),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  /// Top Cajeros del período (BI Fase 3): monto, facturas y % del total.
  Widget _buildTopCajeros() {
    if (_cargandoSerie) return const SizedBox.shrink();
    final lista =
        (_serie?['rendimientoCajeros'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    if (lista.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final totalMontoBs = lista.fold<double>(
      0,
      (total, c) => total + _parseNum(c['montoBs']),
    );
    final maxMontoBs = lista
        .map((c) => _parseNum(c['montoBs']))
        .fold<double>(0, (m, v) => v > m ? v : m);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Rendimiento por Cajero',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...lista.take(6).map((c) {
              final montoBs = _parseNum(c['montoBs']);
              final ticketBs = _parseNum(c['ticketPromedioBs']);
              final pct = totalMontoBs > 0
                  ? (montoBs / totalMontoBs) * 100
                  : 0.0;
              final frac = maxMontoBs > 0
                  ? (montoBs / maxMontoBs).clamp(0.0, 1.0)
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c['nombre']} · ${c['rol']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          'Bs. ${_moneda(montoBs)} · ${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 8,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_num(c['facturas'])} factura(s) · Ticket Bs. ${_moneda(ticketBs)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═══════════════ MOTOR DE INSIGHTS INTELIGENTES (Fase 8) ═══════════════
  // Reglas de negocio que derivan recomendaciones accionables de la serie
  // financiera ya cargada (cero llamadas extra al backend).

  /// Genera la lista de insights del período activo, ordenada por prioridad.
  List<
    ({
      IconData icon,
      Color color,
      String titulo,
      String mensaje,
      VoidCallback? accion,
      String? accionTexto,
    })
  >
  _generarInsights() {
    final insights =
        <
          ({
            IconData icon,
            Color color,
            String titulo,
            String mensaje,
            VoidCallback? accion,
            String? accionTexto,
          })
        >[];
    final s = _serie;
    if (s == null) return insights;

    final ventas = (s['ventas'] as Map<String, dynamic>?) ?? const {};
    final rent = (s['rentabilidad'] as Map<String, dynamic>?) ?? const {};
    final serie =
        (s['serie'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final caja =
        (s['cajaDiaria'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final alertas = (s['alertasStock'] as List<dynamic>?) ?? const [];
    final conteoAlertas =
        (s['conteoAlertasStock'] as num?)?.toInt() ?? alertas.length;

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
          accion: () => _navegar(InventarioScreen()),
          accionTexto: 'Revisar producto',
        ));
      } else if (pctMargen >= 30) {
        insights.add((
          icon: Icons.trending_up,
          color: Colors.green,
          titulo: 'Excelente margen (${pctMargen.toStringAsFixed(1)}%)',
          mensaje: 'La rentabilidad del período supera el 30%. Momento ideal para negociar volumen con proveedores o invertir en stock de alta rotación.',
          accion: () => _navegar(FacturasScreen(periodoInicial: _periodo)),
          accionTexto: 'Ver facturas',
        ));
      } else {
        insights.add((
          icon: Icons.percent,
          color: Colors.blueAccent,
          titulo: 'Margen saludable (${pctMargen.toStringAsFixed(1)}%)',
          mensaje:
              'Ganancia de \$${_moneda(margenUsd)} en el período. Un empuje del 5% en el ticket promedio sumaría \$${_moneda(margenUsd * 0.05 / (pctMargen / 100))} adicionales.',
          accion: () => _navegar(FacturasScreen(periodoInicial: _periodo)),
          accionTexto: 'Ver facturas',
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
            accion: () => _navegar(InventarioScreen()),
            accionTexto: 'Revisar producto',
          ));
        } else if (variacion >= 15) {
          insights.add((
            icon: Icons.rocket_launch,
            color: Colors.green,
            titulo: 'Ventas al alza (+${variacion.toStringAsFixed(0)}%)',
            mensaje:
                'Bs. ${_moneda(actual)} en el último tramo (+${variacion.toStringAsFixed(0)}%). Asegura stock del Top 5 para no perder la racha.',
            accion: () => _navegar(InventarioScreen()),
            accionTexto: 'Revisar producto',
          ));
        }
      }
    }

    // 2b) Contexto vs. PROMEDIO del período (lectura de un vistazo).
    if (serie.length >= 4) {
      final valores = serie.map((f) => _parseNum(f['montoBs'])).toList();
      final promedio = valores.reduce((a, b) => a + b) / valores.length;
      final ultimo = valores.last;
      if (promedio > 0) {
        final desvio = ((ultimo - promedio) / promedio) * 100;
        if (desvio.abs() >= 25) {
          insights.add((
            icon: desvio > 0 ? Icons.insights : Icons.trending_flat,
            color: desvio > 0 ? Colors.green : Colors.orange,
            titulo: desvio > 0
                ? 'Último tramo ${desvio.toStringAsFixed(0)}% sobre el promedio'
                : 'Último tramo ${desvio.abs().toStringAsFixed(0)}% bajo el promedio',
            mensaje:
                'Promedio del período: Bs. ${_moneda(promedio)}. El tramo "${serie.last['etiqueta']}" cerró en Bs. ${_moneda(ultimo)}.',
            accion: null,
            accionTexto: null,
          ));
        }
      }
    }

    // 2c) PICO inusual: un tramo que supera 2× la mediana del período.
    if (serie.length >= 5) {
      final orden = serie.map((f) => _parseNum(f['montoBs'])).toList()..sort();
      final mediana = orden[orden.length ~/ 2];
      final pico = serie.reduce(
        (a, b) => _parseNum(a['montoBs']) >= _parseNum(b['montoBs']) ? a : b,
      );
      final picoVal = _parseNum(pico['montoBs']);
      if (mediana > 0 && picoVal >= mediana * 2) {
        insights.add((
          icon: Icons.bolt,
          color: Colors.deepPurple,
          titulo: 'Pico inusual: ${pico['etiqueta']}',
          mensaje:
              'Bs. ${_moneda(picoVal)} — más del doble de la mediana del período (Bs. ${_moneda(mediana)}). Revisa si hubo una venta mayorista o promoción.',
          accion: null,
          accionTexto: null,
        ));
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
          accion: null,
          accionTexto: null,
        ));
      }
    }

    // 4) Stock crítico: productos en o bajo el mínimo.
    if (conteoAlertas > 0) {
      final primero = (alertas.first as Map).cast<String, dynamic>();
      insights.add((
        icon: Icons.inventory,
        color: Colors.amber.shade800,
        titulo: '$conteoAlertas producto(s) en stock mínimo',
        mensaje:
            '"${primero['Nombre']}" está al límite. Genera la nota de entrada antes de que la venta lo agote.',
        accion: () => _navegar(InventarioScreen()),
        accionTexto: 'Revisar producto',
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
            titulo:
                '${dominante['metodo']}: ${pct.toStringAsFixed(0)}% de los cobros',
            mensaje: 'Fuerte concentración en un solo método. Verifica que el flujo de caja físico cubra los egresos en efectivo del día.',
            accion: () => _navegar(FinanzasScreen()),
            accionTexto: 'Ver caja',
          ));
        }
      }
    }

    // 6) Asistente de Negocio (analítica de 30 días del backend).
    final asist = (s['asistente'] as Map<String, dynamic>?) ?? const {};
    final muerto =
        (asist['inventarioMuerto'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final margenLista =
        (asist['alertasMargen'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final rot = (asist['rotacion'] as Map<String, dynamic>?) ?? const {};
    final mayor =
        (rot['mayorRotacion'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (muerto.isNotEmpty) {
      final valMuerto = muerto.fold<double>(
        0,
        (t, p) => t + _parseNum(p['valorDolares']),
      );
      final p1 = muerto.first;
      insights.add((
        icon: Icons.dangerous,
        color: Theme.of(context).colorScheme.error,
        titulo: 'Inventario muerto: ${muerto.length} producto(s)',
        mensaje:
            '\$${_moneda(valMuerto)} estancados sin ventas en 30 días. Ej: "${p1['nombre']}" (${p1['stock']} uds). Promociona o descuenta por lote.',
        accion: () => _navegar(InventarioScreen()),
        accionTexto: 'Revisar producto',
      ));
    }

    for (final p in margenLista.take(3)) {
      final pct = _parseNum(p['margenPct']);
      final perdida = pct < 0;
      insights.add((
        icon: Icons.trending_down,
        color: perdida ? Theme.of(context).colorScheme.error : Colors.orange,
        titulo: 'Margen ${perdida ? 'a pérdida' : 'bajo'} · ${p['nombre']}',
        mensaje:
            '${pct.toStringAsFixed(1)}% (precio \$${_moneda(p['precioDolar'])} vs costo \$${_moneda(p['costoDolar'])}). Reevalúa costo de compra o precio.',
        accion: () => _navegar(InventarioScreen()),
        accionTexto: 'Revisar producto',
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
        accion: () => _navegar(InventarioScreen()),
        accionTexto: 'Revisar producto',
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
          accion: () => _navegar(
            EntradasScreen(productoInicialId: (p['id'] as num?)?.toInt()),
          ),
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
            Icon(
              Icons.auto_awesome,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'Asistente de Negocio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...insights
            .take(7)
            .map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 1,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  i.mensaje,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                                          minHeight: 48,
                                        ),
                                        child: FilledButton.tonalIcon(
                                          onPressed: i.accion,
                                          icon: Icon(i.icon, size: 16),
                                          label: Text(
                                            i.accionTexto!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (i.accion != null)
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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

  /// Tendencia de ventas: gráfico BI (histograma con valores DIRECTOS +
  /// línea temporal) con tipografía ampliada para PC. Reemplaza las barras
  /// anteriores que exigían pasar el cursor para ver el monto del día.
  Widget _buildTendenciaVentas() {
    final tituloSerie = switch (_periodo) {
      'hoy' => 'Ventas por Hora (Hoy)',
      'semana' => 'Ventas por Día (Últimos 7 días)',
      'mes' => 'Ventas por Día (Mes Actual)',
      _ => 'Ventas por Mes (Año Actual)',
    };

    if (_cargandoSerie) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final serie =
        (_serie?['serie'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    return BiSerieChart(
      titulo: tituloSerie,
      serie: serie.map(PuntoSerie.fromJson).toList(),
      enBs: true,
    );
  }

  /// Desglose de caja diaria por método de pago + alertas de stock.
  /// Top 5 productos más vendidos del periodo seleccionado (BI, Fase 6).
  Widget _buildTopProductos() {
    if (_cargandoSerie || _errorSerie != null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final top =
        (_serie?['topProductos'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final maxUnidades = top.fold<double>(0, (m, p) {
      final u = (p['unidades'] as num? ?? 0).toDouble();
      return u > m ? u : m;
    });

    // Podio: oro, plata, bronce; el resto en slate.
    const medallas = [Color(0xFFF59E0B), Color(0xFF94A3B8), Color(0xFFB45309)];
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
              'Top 10 Productos Más Vendidos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    mensaje: 'Cuando realices tu primera venta, aquí aparecerán tus productos estrella.',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < top.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Miniatura WebP del catálogo EPA (resuelta a
                              // absoluta vía ApiService.urlImagen) + medalla.
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: cs.surfaceContainerHighest,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: _miniaturaTop(
                                        top[i]['imagenUrl'],
                                        92,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -4,
                                    left: -4,
                                    child: CircleAvatar(
                                      radius: 11,
                                      backgroundColor: colorPosicion(i),
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (top[i]['nombre'] ?? '').toString(),
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if ((top[i]['marca'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          top[i]['marca'].toString(),
                                        if ((top[i]['categoria'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          top[i]['categoria'].toString(),
                                      ].join('  ·  ').trim(),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: maxUnidades > 0
                                            ? ((top[i]['unidades'] as num? ?? 0)
                                                          .toDouble() /
                                                      maxUnidades)
                                                  .clamp(0.02, 1.0)
                                            : 0.02,
                                        child: Container(
                                          height: 5,
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
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
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

  /// Miniatura WebP para el Top de Productos. Resuelve rutas relativas
  /// (`/productos/SKU.webp`) a absolutas vía [ApiService.urlImagen] y degrada
  /// a un ícono si no hay imagen o falla la carga (catálogo EPA servido por
  /// el backend). [px] = ancho en píxeles de dispositivo pedido a la caché.
  Widget _miniaturaTop(dynamic ruta, int px) {
    final url = ApiService.urlImagen(ruta?.toString());
    if (url == null) {
      return const Center(
        child: Icon(Icons.inventory_2_outlined, size: 22, color: Colors.grey),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: px,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.inventory_2_outlined, size: 22, color: Colors.grey),
      ),
      loadingBuilder: (ctx, child, prog) => prog == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildCajaDiaria() {
    final caja =
        (_serie?['cajaDiaria'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final alertas =
        (_serie?['alertasStock'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final idsBajoStock =
        (_serie?['idsBajoStock'] as List<dynamic>?)
            ?.whereType<num>()
            .map((id) => id.toInt())
            .toList() ??
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: caja.isEmpty
                ? _estadoVacio(
                    icono: Icons.point_of_sale_outlined,
                    titulo: 'Sin ventas de hoy todavía',
                    mensaje: 'Abre una venta desde “Vender” y los cobros aparecerán aquí separados por método de pago.',
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                        subtitle: Text(
                          'Stock: ${p['Stock_Actual']} (Mín: ${p['Stock_Minimo']})',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                        // Banner accionable → Entradas con precarga de los
                        // productos con quiebre (producto tocado preseleccionado).
                        onTap: () {
                          final ids = idsBajoStock;
                          _navegar(
                            EntradasScreen(
                              productoInicialId: (p['Producto_ID'] as num?)
                                  ?.toInt(),
                              idsBajoStock: ids,
                            ),
                          );
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
          Icon(
            icono,
            size: 44,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
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
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 620;
        final acciones = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _navegar(PosScreen()),
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: const Text('Nueva venta'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cs.primary,
                minimumSize: const Size(48, 44),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _navegar(InventarioScreen()),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Inventario'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.65)),
                minimumSize: const Size(48, 44),
              ),
            ),
          ],
        );
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compacto ? 18 : 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.7)!],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: compacto
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _identidadEncabezado(),
                    const SizedBox(height: 18),
                    acciones,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _identidadEncabezado()),
                    const SizedBox(width: 16),
                    acciones,
                  ],
                ),
        );
      },
    );
  }

  Widget _identidadEncabezado() {
    final ahora = DateTime.now();
    const dias = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final fecha =
        '${dias[ahora.weekday - 1]}, ${ahora.day} de ${meses[ahora.month - 1]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: const Icon(Icons.storefront, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ferretería Adrialga C.A.',
                style: TextStyle(
                  fontSize: MediaQuery.sizeOf(context).width < 600 ? 20 : 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Ventas, inventario y caja bajo control',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    fecha,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
            if (badge != null) ...[const SizedBox(height: 6), badge],
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
        return _badge(
          '${resumen['totalProveedores'] ?? 0} reg.',
          Colors.indigo,
        );
      case 2: // Facturas & Ventas
        return _badge(
          '${resumen['totalFacturas'] ?? 0} emitidas',
          Colors.green,
        );
      case 5: // Entradas & Inventario → alerta stock bajo
        // Sin casteo directo: el conteo puede venir como String desde la API.
        final stockBajo =
            (double.tryParse(alertas['conteoStockBajo']?.toString() ?? '') ?? 0)
                .toInt();
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
          const Icon(
            Icons.warning_amber_rounded,
            size: 11,
            color: Colors.white,
          ),
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
    _desplazamiento =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.elasticOut,
            reverseCurve: Curves.easeIn,
          ),
        );
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
