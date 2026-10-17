import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/monitor_window.dart';
import '../services/socket_service.dart';

/// Monitor de Base de Datos — pantalla independiente de la app principal.
///
/// Dibuja el esquema REAL de la base (leído de information_schema vía
/// `GET /api/monitor/esquema`) con estética tipo drawdb: nodos de tabla,
/// aristas de claves foráneas, zoom/pan y nodos arrastrables. Se ilumina en
/// tiempo real cada vez que el backend emite un `db_update` (Socket.IO):
///   · el nodo afectado late y sus FILAS se recorren con una banda verde;
///   · las ARISTAS FK conectadas reciben un pulso que viaja por la curva;
///   · el panel derecho registra la actividad (módulo, mensaje, hora).
///
/// Dos vistas:
///   · presentacion → las 12 tablas del modelo expuesto (por defecto).
///   · full         → todas las tablas de la base.
///
/// Al abrirse la vista se AJUSTA SOLA al tamaño de la ventana (fit-to-screen),
/// de modo que las 12 tablas se vean completas sin tener que hacer zoom. Con el
/// botón «Abrir en ventana» (solo web) se puede lanzar el Monitor en su propia
/// pestaña y colocarlo al lado de la aplicación durante la demostración.
class MonitorDbScreen extends StatefulWidget {
  /// 'presentacion' | 'full'
  final String modoInicial;

  /// `true` cuando la pantalla se abrió como vista suelta (fragmento `#monitor`)
  /// en su propia pestaña: sin botón «atrás» y con el registro abierto.
  final bool independiente;

  const MonitorDbScreen({
    super.key,
    this.modoInicial = 'presentacion',
    this.independiente = false,
  });

  @override
  State<MonitorDbScreen> createState() => _MonitorDbScreenState();
}

/// Mapa módulo (evento db_update) → tablas que se iluminan en el diagrama.
const Map<String, List<String>> _moduloTablas = {
  'ventas': [
    'facturas',
    'detalle_facturas',
    'pagos',
    'movimientos_caja',
    'productos',
  ],
  'caja': ['caja', 'movimientos_caja'],
  'finanzas': ['cuentas_por_pagar', 'movimientos_caja'],
  'inventario': [
    'productos',
    'producto_variantes',
    'variante_atributos',
    'notas_entrega_entrada',
    'detalle_notas_entrega',
  ],
  'proveedores': ['proveedores', 'cuentas_por_pagar'],
  'clientes': ['clientes'],
  'categorias': ['categorias', 'productos'],
  'usuarios': ['usuarios'],
  'configuracion': ['configuracion_tienda'],
  'tasa': ['tasas_bcv'],
  'scraping': ['productos'],
};

class _MonitorDbScreenState extends State<MonitorDbScreen>
    with SingleTickerProviderStateMixin {
  late String _modo;
  bool _cargando = true;
  String? _error;

  List<_TablaNodo> _tablas = [];
  List<_Relacion> _relaciones = [];
  String? _base;
  Map<String, dynamic> _resumen = const {};

  // Geometría del diagrama (offsets por nombre de tabla).
  final Map<String, Offset> _posiciones = {};
  final Map<String, Size> _tamanos = {};

  // Actividad en vivo.
  final List<_EventoDb> _eventos = [];
  final Set<String> _resaltadas = {};
  Timer? _temporizadorResaltado;
  final TransformationController _transform = TransformationController();
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  // El panel de actividad arranca OCULTO: el diagrama necesita todo el ancho
  // para que las 12 tablas se vean grandes y completas (antes el panel le
  // robaba ~300 px y el diagrama quedaba recortado). Se abre con el botón.
  bool _panelVisible = false;

  // Búsqueda de navegación: localiza tablas por nombre o por columna.
  final TextEditingController _busquedaController = TextEditingController();
  String _busqueda = '';
  final Set<String> _coincidencias = {};

  /// Tamaño real del lienzo (lo reporta el LayoutBuilder). Se usa para ajustar
  /// el diagrama a la ventana en cuanto hay datos.
  Size _vpSize = Size.zero;
  bool _pendienteAjuste = true;
  bool _usuarioManipulo = false;

  static const double _anchoNodo = 236;
  static const double _altoFilaHeader = 34;
  static const double _altoSubheader = 18;
  static const double _altoFilaColumna = 18.5;
  static const double _gapX = 88;
  static const double _gapY = 58;
  static const double _margen = 40;

  @override
  void initState() {
    super.initState();
    _modo = widget.modoInicial;
    // La vista suelta necesita su propio canal de eventos: el shell no está
    // montado en esa pestaña. `start()` es idempotente.
    SocketService.start();
    SocketService.onDbUpdateEvento(_alEventoDb);
    _cargar();
  }

  @override
  void dispose() {
    SocketService.offDbUpdateEvento(_alEventoDb);
    _temporizadorResaltado?.cancel();
    _busquedaController.dispose();
    _pulso.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final data = await ApiService.getMonitorEsquema(modo: _modo);
      final tablas = <_TablaNodo>[];
      for (final t in (data['tablas'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(t as Map);
        tablas.add(_TablaNodo.fromJson(m));
      }
      final relaciones = <_Relacion>[];
      for (final r in (data['relaciones'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(r as Map);
        relaciones.add(_Relacion.fromJson(m));
      }
      if (!mounted) return;
      setState(() {
        _tablas = tablas;
        _relaciones = relaciones;
        _base = data['base']?.toString();
        _resumen = data['resumen'] is Map
            ? Map<String, dynamic>.from(data['resumen'] as Map)
            : const {};
        _error = null;
        _cargando = false;
      });
      _calcularLayout();
      // La búsqueda sobrevive a una recarga: se vuelve a aplicar para que las
      // coincidencias sigan resaltadas tras refrescar el esquema.
      if (mounted && _busqueda.isNotEmpty) _aplicarBusqueda(_busqueda);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo leer el esquema: $e';
      });
    }
  }

  /// Alto real de un nodo (encabezado + subtítulo de activos + filas).
  double _altoNodo(_TablaNodo t) {
    var alto = _altoFilaHeader + t.columnas.length * _altoFilaColumna + 10;
    if (t.activos != null) alto += _altoSubheader;
    return alto;
  }

  /// Distribuye las tablas en una cuadrícula estable. Se recalcula solo cuando
  /// cambia el conjunto de tablas (no en cada resaltado).
  ///
  /// El número de columnas se ELIGE para que la proporción de la cuadrícula se
  /// parezca a la de la ventana: así el ajuste automático (fit) deja el
  /// diagrama ocupando toda el área en vez de quedar como una franja pequeña.
  void _calcularLayout() {
    if (_tablas.isEmpty) {
      if (!mounted) return;
      setState(() {
        _posiciones.clear();
        _tamanos.clear();
      });
      return;
    }

    final n = _tablas.length;
    final columnas = _mejorNumeroDeColumnas(n);

    final porFila = <double>[];
    final pos = <String, Offset>{};
    final tam = <String, Size>{};

    for (var i = 0; i < n; i++) {
      final t = _tablas[i];
      final size = Size(_anchoNodo, _altoNodo(t));
      tam[t.nombre] = size;
      final fila = i ~/ columnas;
      final col = i % columnas;
      while (porFila.length <= fila) {
        porFila.add(0);
      }
      porFila[fila] = math.max(porFila[fila], size.height);
      pos[t.nombre] = Offset(
        _margen + col * (_anchoNodo + _gapX),
        _margen + _sumaFilas(porFila, fila),
      );
    }
    if (!mounted) return;
    setState(() {
      _posiciones
        ..clear()
        ..addAll(pos);
      _tamanos
        ..clear()
        ..addAll(tam);
    });
    _pendienteAjuste = true;
    _usuarioManipulo = false;
    _programarAjuste();
  }

  /// Prueba 3..6 columnas y devuelve la que produce una cuadrícula con la
  /// proporción más cercana a la del lienzo disponible.
  int _mejorNumeroDeColumnas(int n) {
    final objetivo = _vpSize.isEmpty || _vpSize.height <= 0
        ? 16 / 9
        : _vpSize.width / _vpSize.height;
    // Preferir cuadrículas SIN huecos: si `n` se reparte exacto entre las
    // columnas candidatas, no queda una última fila a medias. Para las 12
    // tablas esto permite 6×2 (llena todo el ancho) o 4×3, en vez de 5×3 con
    // tres huecos a la derecha.
    final candidatos = [3, 4, 5, 6].where((c) => c <= n).toList();
    final divisores = candidatos.where((c) => n % c == 0).toList();
    final pool = divisores.isNotEmpty ? divisores : candidatos;

    // Pantalla ancha (proyector/desktop): más columnas = mejor uso del ancho.
    if (objetivo >= 1.7 && pool.contains(6)) return 6;

    var mejor = pool.first;
    var mejorError = double.infinity;
    for (final c in pool) {
      final filas = (n / c).ceil();
      final ancho = c * _anchoNodo + (c - 1) * _gapX;
      final alto = filas * 300 + (filas - 1) * _gapY;
      final error = (ancho / alto - objetivo).abs();
      if (error < mejorError) {
        mejorError = error;
        mejor = c;
      }
    }
    return mejor;
  }

  double _sumaFilas(List<double> alturas, int hasta) {
    var total = 0.0;
    for (var i = 0; i < hasta && i < alturas.length; i++) {
      total += alturas[i] + _gapY;
    }
    return total;
  }

  /// Encola el ajuste para el siguiente frame: el lienzo ya tendrá su tamaño.
  void _programarAjuste() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ajustarVista();
    });
  }

  /// Escala y centra el diagrama completo dentro del área visible.
  void _ajustarVista() {
    if (_posiciones.isEmpty || _vpSize.width <= 0 || _vpSize.height <= 0) {
      return;
    }
    var contenidoW = 0.0;
    var contenidoH = 0.0;
    for (final t in _tablas) {
      final p = _posiciones[t.nombre];
      final s = _tamanos[t.nombre];
      if (p == null || s == null) continue;
      contenidoW = math.max(contenidoW, p.dx + s.width);
      contenidoH = math.max(contenidoH, p.dy + s.height);
    }
    if (contenidoW <= 0 || contenidoH <= 0) return;

    // Margen mínimo (10 px) para aprovechar toda la pantalla; y se permite
    // ampliar hasta 1.6× cuando el contenido es pequeño, en vez de dejarlo
    // diminuto con franjas vacías alrededor.
    const pad = 10.0;
    final escala = math.min(
      1.6,
      math.min(
        (_vpSize.width - pad * 2) / contenidoW,
        (_vpSize.height - pad * 2) / contenidoH,
      ),
    );
    final tx = (_vpSize.width - contenidoW * escala) / 2;
    final ty = (_vpSize.height - contenidoH * escala) / 2;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, escala)
      ..setEntry(1, 1, escala)
      ..setEntry(2, 2, escala)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    _pendienteAjuste = false;
  }

  void _alEventoDb(Map<String, dynamic> evento) {
    if (!mounted) return;
    final modulo = evento['modulo']?.toString() ?? '';
    final mensaje = evento['mensaje']?.toString() ?? 'Cambio en la base de datos';
    final hora = DateTime.tryParse(evento['timestamp']?.toString() ?? '') ??
        DateTime.now();
    final tablas = _moduloTablas[modulo] ?? const <String>[];

    setState(() {
      _eventos.insert(
        0,
        _EventoDb(modulo: modulo, mensaje: mensaje, hora: hora, tablas: tablas),
      );
      if (_eventos.length > 200) _eventos.removeRange(200, _eventos.length);
      // Solo se resaltan tablas visibles en el modo actual.
      final visibles = _tablas.map((t) => t.nombre).toSet();
      _resaltadas
        ..clear()
        ..addAll(tablas.where(visibles.contains));
    });

    // El pulso solo corre mientras hay actividad: sin eventos no se repinta.
    if (_resaltadas.isNotEmpty && !_pulso.isAnimating) {
      _pulso.repeat();
    }

    _temporizadorResaltado?.cancel();
    _temporizadorResaltado = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _resaltadas.clear());
      _pulso.stop();
      _pulso.value = 0;
    });
  }

  void _cambiarModo(String modo) {
    if (modo == _modo) return;
    setState(() {
      _modo = modo;
      _resaltadas.clear();
      _pendienteAjuste = true;
      _usuarioManipulo = false;
    });
    _pulso.stop();
    _cargar();
  }

  void _resetVista() {
    _usuarioManipulo = false;
    _ajustarVista();
  }

  /// Resalta en el diagrama las tablas cuyo nombre, o alguna de sus columnas,
  /// coincida con la búsqueda. Reutiliza el resaltado de la actividad en vivo,
  /// así las coincidencias "laten" igual que un nodo afectado por un cambio.
  ///
  /// La búsqueda PERSISTE: se cancela el temporizador que borra el resaltado
  /// automático a los 1,8 s (propio de los eventos `db_update`).
  void _aplicarBusqueda(String q) {
    final consulta = q.trim().toLowerCase();
    _temporizadorResaltado?.cancel();

    if (consulta.isEmpty) {
      setState(() {
        _busqueda = q;
        _coincidencias.clear();
        _resaltadas.clear();
      });
      _pulso.stop();
      _pulso.value = 0;
      return;
    }

    final encontradas = <String>{};
    for (final t in _tablas) {
      final porNombre = t.nombre.toLowerCase().contains(consulta);
      final porColumna =
          t.columnas.any((c) => c.nombre.toLowerCase().contains(consulta));
      if (porNombre || porColumna) encontradas.add(t.nombre);
    }

    setState(() {
      _busqueda = q;
      _coincidencias
        ..clear()
        ..addAll(encontradas);
      _resaltadas
        ..clear()
        ..addAll(encontradas);
    });

    if (encontradas.isNotEmpty) {
      if (!_pulso.isAnimating) _pulso.repeat();
    } else {
      _pulso.stop();
      _pulso.value = 0;
    }
  }

  void _abrirEnVentana() {
    final url = Uri.base
        .replace(fragment: 'monitor', queryParameters: const {})
        .toString();
    final ok = abrirMonitorWindow(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            monitorWindowDisponible
                ? 'El navegador bloqueó la ventana emergente. Permita las ventanas emergentes para este sitio.'
                : 'Abrir en otra ventana solo está disponible en la versión web.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.independiente,
        backgroundColor: const Color(0xFF111C33),
        foregroundColor: const Color(0xFFE2E8F0),
        titleSpacing: widget.independiente ? 16 : 0,
        title: Row(
          children: [
            const Icon(Icons.storage, size: 20),
            const SizedBox(width: 10),
            const Text('Monitor de Base de Datos'),
            const SizedBox(width: 12),
            if (_base != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  _base!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF93C5FD),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const Spacer(),
            SizedBox(
              width: 235,
              height: 34,
              child: TextField(
                controller: _busquedaController,
                style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
                cursorColor: const Color(0xFF93C5FD),
                onChanged: _aplicarBusqueda,
                decoration: InputDecoration(
                  hintText: 'Buscar tabla o columna…',
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Color(0x66CBD5E1)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: Color(0x88CBD5E1)),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          iconSize: 15,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 26, minHeight: 26),
                          color: const Color(0x99CBD5E1),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _busquedaController.clear();
                            _aplicarBusqueda('');
                          },
                        ),
                  filled: true,
                  fillColor: const Color(0xFF0F1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF60A5FA)),
                  ),
                ),
              ),
            ),
            if (_busqueda.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF14532D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF22C55E)),
                ),
                child: Text(
                  '${_coincidencias.length}/${_tablas.length}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (monitorWindowDisponible)
            IconButton(
              tooltip: 'Abrir en otra pestaña / ventana',
              icon: const Icon(Icons.open_in_new),
              onPressed: _abrirEnVentana,
            ),
          IconButton(
            tooltip: 'Recargar esquema',
            icon: const Icon(Icons.refresh),
            onPressed: () => _cargar(silencioso: true),
          ),
          IconButton(
            tooltip: _panelVisible ? 'Ocultar registro' : 'Mostrar registro',
            icon: Icon(_panelVisible ? Icons.chevron_right : Icons.chevron_left),
            onPressed: () {
              setState(() => _panelVisible = !_panelVisible);
              // Al cambiar el ancho disponible, reajustar para que TODAS las
              // tablas vuelvan a caber (antes quedaban recortadas).
              _usuarioManipulo = false;
              _programarAjuste();
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _estadoError(cs)
              : Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _lienzo(cs)),
                          if (_panelVisible) _panelRegistro(cs),
                        ],
                      ),
                    ),
                    _barraInferior(cs),
                  ],
                ),
    );
  }

  Widget _estadoError(ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 42, color: Color(0xFFFCA5A5)),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Error desconocido',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _cargar(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lienzo(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vp = Size(constraints.maxWidth, constraints.maxHeight);
        if (vp != _vpSize) {
          _vpSize = vp;
          // Reajustar al redimensionar solo si el usuario no ha movido la vista
          // a mano (si la movió, respetamos su encuadre).
          // Reajustar SIEMPRE que cambie el área disponible (redimensionar,
          // abrir/cerrar el panel). Antes se respetaba el encuadre manual y el
          // diagrama quedaba recortado sin forma de recuperarlo salvo el botón.
          _programarAjuste();
        }

        // El lienzo debe abarcar el CONTENIDO REAL: borde derecho/inferior de
        // cada nodo (posición + su tamaño), no solo su esquina superior. Antes
        // se usaba `max(dy) + 300`, que recortaba las tablas altas de la última
        // fila (productos tiene 16 columnas) y dejaba espacio muerto.
        final ancho = _posiciones.isEmpty
            ? 1200.0
            : _posiciones.entries
                    .map((e) =>
                        e.value.dx + (_tamanos[e.key]?.width ?? _anchoNodo))
                    .reduce(math.max) +
                40;
        final alto = _posiciones.isEmpty
            ? 800.0
            : _posiciones.entries
                    .map((e) =>
                        e.value.dy + (_tamanos[e.key]?.height ?? 300))
                    .reduce(math.max) +
                40;

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                // `constrained: false` es IMPRESCINDIBLE: con el valor por
                // defecto (true) el hijo se fuerza al tamaño del viewport y
                // todo lo que exceda ese alto/ancho se RECORTA (la tercera
                // fila de tablas desaparecía y quedaba una franja vacía).
                // Sin restricción, el lienzo conserva su tamaño real y el
                // encaje (fit) puede mostrarlo completo.
                constrained: false,
                minScale: 0.15,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(600),
                onInteractionStart: (_) => _usuarioManipulo = true,
                child: SizedBox(
                  width: ancho,
                  height: alto,
                  child: Stack(
                    children: [
                      // Aristas FK (debajo de los nodos).
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _pulso,
                          builder: (_, __) => CustomPaint(
                            painter: _AristasPainter(
                              relaciones: _relaciones,
                              posiciones: _posiciones,
                              tamanos: _tamanos,
                              resaltadas: _resaltadas,
                              fase: _pulso.value,
                            ),
                          ),
                        ),
                      ),
                      for (final t in _tablas)
                        Positioned(
                          left: _posiciones[t.nombre]?.dx ?? 0,
                          top: _posiciones[t.nombre]?.dy ?? 0,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              final actual = _posiciones[t.nombre];
                              if (actual == null) return;
                              _usuarioManipulo = true;
                              setState(() {
                                _posiciones[t.nombre] = actual + d.delta;
                              });
                            },
                            child: _nodoTabla(t),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Leyenda + zoom (esquina inferior derecha, sobre el lienzo).
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [_leyenda(), const SizedBox(height: 6), _controlesZoom()],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Barra inferior: conmutador de vista (izquierda), totales (centro) y aviso
  /// del modo activo. Antes el conmutador flotaba con opacidad 0.62 sobre el
  /// diagrama y se recortaba en ventanas pequeñas.
  Widget _barraInferior(ColorScheme cs) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1A2E),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _botonModo('presentacion', '12 tablas', 'Modelo expuesto (12 tablas)'),
          const SizedBox(width: 8),
          _botonModo('full', 'completa', 'Todas las tablas de la base'),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _dato('${_resumen['tablas'] ?? _tablas.length}', 'tablas'),
                  if (_resumen['filas'] != null)
                    _dato(_miles(_resumen['filas']), 'filas'),
                  if (_resumen['activos'] != null)
                    _dato(_miles(_resumen['activos']), 'activos', verde: true),
                ],
              ),
            ),
          ),
          Text(
            _modo == 'presentacion'
                ? 'Vista de presentación · modelo expuesto'
                : 'Vista completa · toda la base',
            style: const TextStyle(fontSize: 11, color: Color(0x77CBD5E1)),
          ),
        ],
      ),
    );
  }

  Widget _dato(dynamic valor, String etiqueta, {bool verde = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: verde ? const Color(0xFF6EE7B7) : const Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 11, color: Color(0x88CBD5E1)),
          ),
        ],
      ),
    );
  }

  Widget _botonModo(String modo, String etiqueta, String tooltip) {
    final sel = _modo == modo;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _cambiarModo(modo),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF1D4ED8) : const Color(0xFF16213A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel ? const Color(0xFF60A5FA) : const Color(0xFF2B3A55),
            ),
          ),
          child: Text(
            etiqueta,
            style: TextStyle(
              fontSize: 12,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? const Color(0xFFE2E8F0) : const Color(0x99CBD5E1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leyenda() {
    Widget item(Color color, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                texto,
                style: const TextStyle(fontSize: 11, color: Color(0x99CBD5E1)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0F1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item(const Color(0xFFFBBF24), 'PK'),
          item(const Color(0xFF60A5FA), 'FK'),
          item(const Color(0xFF34D399), 'actividad en vivo'),
        ],
      ),
    );
  }

  Widget _controlesZoom() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0F1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Alejar',
            iconSize: 18,
            color: const Color(0xFFCBD5E1),
            onPressed: () {
              final m = _transform.value.clone()..scale(1 / 1.2);
              _transform.value = m;
              _usuarioManipulo = true;
            },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Ajustar a la ventana',
            iconSize: 18,
            color: const Color(0xFFCBD5E1),
            onPressed: _resetVista,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          IconButton(
            tooltip: 'Acercar',
            iconSize: 18,
            color: const Color(0xFFCBD5E1),
            onPressed: () {
              final m = _transform.value.clone()..scale(1.2);
              _transform.value = m;
              _usuarioManipulo = true;
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _nodoTabla(_TablaNodo t) {
    final activa = _resaltadas.contains(t.nombre);
    if (!activa) return _nodoBase(t, 0);
    return AnimatedBuilder(
      animation: _pulso,
      builder: (_, __) => _nodoBase(t, _pulso.value),
    );
  }

  /// Banda de luz que recorre las filas de una tabla con actividad reciente.
  /// [fase] va de 0 a 1 y desplaza el frente luminoso fila a fila.
  double _intensidadFila(int i, double fase) {
    const ancho = 0.4;
    final p = (fase + i * 0.09) % 1.0;
    if (p > ancho) return 0.0;
    return math.sin((p / ancho) * math.pi);
  }

  Widget _nodoBase(_TablaNodo t, double fase) {
    final activa = _resaltadas.contains(t.nombre);
    final size = _tamanos[t.nombre] ?? const Size(_anchoNodo, 120);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: size.width,
      // Altura explícita: el pintor de aristas ancla las FK al borde del nodo
      // usando `_tamanos`; si la altura fuera intrínseca, las curvas no
      // tocarían el borde real de la tarjeta.
      height: size.height,
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: activa ? const Color(0xFF34D399) : const Color(0xFF334155),
          width: activa ? 2 : 1,
        ),
        boxShadow: activa
            ? [
                BoxShadow(
                  color: Color.lerp(
                    const Color(0x3334D399),
                    const Color(0x8834D399),
                    0.5 + 0.5 * math.sin(fase * 2 * math.pi),
                  )!,
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : const [
                BoxShadow(color: Color(0x66000000), blurRadius: 8),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: activa ? const Color(0xFF14532D) : const Color(0xFF1E3A5F),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  size: 14,
                  color: activa
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFF93C5FD),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                Text(
                  _miles(t.filas),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Subtítulo de "activos": solo en tablas con borrado lógico. Evita la
          // aparente contradicción entre las miles de filas del catálogo y los
          // "100 ítems" activos que muestra el Dashboard.
          if (t.activos != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              height: _altoSubheader,
              color: const Color(0xFF12203A),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 11,
                    color: Color(0xFF6EE7B7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_miles(t.activos!)} activos',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF6EE7B7),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'de ${_miles(t.filas)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0x66CBD5E1),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < t.columnas.length; i++)
            _filaColumna(
              t.columnas[i],
              activa,
              // Sin actividad la banda debe ser 0: `_intensidadFila(i, 0)` NO
              // es cero para i > 0 (el desfase por fila la enciende), así que
              // se corta explícitamente cuando la tabla no está resaltada.
              activa ? _intensidadFila(i, fase) : 0.0,
            ),
        ],
      ),
    );
  }

  Widget _filaColumna(_Columna c, bool activa, double intensidad) {
    final colorIcono = c.pk
        ? const Color(0xFFFBBF24)
        : c.fk
            ? const Color(0xFF60A5FA)
            : const Color(0x44CBD5E1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      color: intensidad <= 0
          ? Colors.transparent
          : const Color(0xFF34D399).withValues(alpha: 0.30 * intensidad),
      child: Row(
        children: [
          Icon(
            c.pk
                ? Icons.vpn_key
                : c.fk
                    ? Icons.link
                    : Icons.circle_outlined,
            size: 11,
            color: colorIcono,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              c.nombre,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: Color.lerp(
                  const Color(0xFFCBD5E1),
                  const Color(0xFF6EE7B7),
                  intensidad,
                ),
              ),
            ),
          ),
          Text(
            _tipoCorto(c.tipo),
            style: const TextStyle(
              fontSize: 10,
              color: Color(0x66CBD5E1),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  static String _tipoCorto(String tipo) {
    final t = tipo.toLowerCase();
    if (t.startsWith('int') || t.startsWith('bigint')) return 'int';
    if (t.startsWith('decimal') || t.startsWith('double')) return 'dec';
    if (t.startsWith('varchar') || t.startsWith('char')) return 'str';
    if (t.startsWith('datetime') || t.startsWith('timestamp')) return 'fecha';
    if (t.startsWith('bool') || t.startsWith('tinyint(1)')) return 'bool';
    if (t.startsWith('date')) return 'fecha';
    return t.length > 6 ? t.substring(0, 6) : t;
  }

  Widget _panelRegistro(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth < 900
            ? 250.0
            : constraints.maxWidth < 1400
                ? 300.0
                : 330.0;
        return Container(
          width: ancho,
          decoration: const BoxDecoration(
            color: Color(0xFF111C33),
            border: Border(left: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, size: 16, color: Color(0xFF34D399)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Actividad en vivo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    Text(
                      '${_eventos.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0x99CBD5E1),
                        fontFamily: 'monospace',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Limpiar registro',
                      iconSize: 16,
                      color: const Color(0x88CBD5E1),
                      onPressed: () => setState(_eventos.clear),
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1E293B)),
              Expanded(
                child: _eventos.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Sin actividad todavía.\nUse el sistema (una venta, una '
                            'compra, un ajuste…) y los eventos aparecerán aquí en '
                            'tiempo real, con las líneas y filas del diagrama '
                            'iluminándose.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 12, color: Color(0x88CBD5E1)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: _eventos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _tarjetaEvento(_eventos[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjetaEvento(_EventoDb e) {
    final hh = e.hora.hour.toString().padLeft(2, '0');
    final mm = e.hora.minute.toString().padLeft(2, '0');
    final ss = e.hora.second.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF243247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.modulo.isEmpty ? 'sistema' : e.modulo,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$hh:$mm:$ss',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0x66CBD5E1),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            e.mensaje,
            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
          ),
          if (e.tablas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in e.tablas)
                  Text(
                    t,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0x8834D399),
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Formatea con separador de miles (7.278). Sin dependencias extra.
String _miles(dynamic v) {
  final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

// ─────────────────────────── Modelos y pintor ────────────────────────────────

class _TablaNodo {
  final String nombre;
  final int filas;

  /// Filas con `Activo = 1`; `null` si la tabla no tiene borrado lógico.
  final int? activos;
  final List<_Columna> columnas;

  _TablaNodo({
    required this.nombre,
    required this.filas,
    required this.activos,
    required this.columnas,
  });

  factory _TablaNodo.fromJson(Map<String, dynamic> j) => _TablaNodo(
        nombre: j['nombre']?.toString() ?? '',
        // Sin casteos: el backend puede mandar estos conteos como String.
        filas: (double.tryParse(j['filas']?.toString() ?? '') ?? 0).toInt(),
        activos: j['activos'] == null
            ? null
            : (double.tryParse(j['activos'].toString()) ?? 0).toInt(),
        columnas: [
          for (final c in (j['columnas'] as List? ?? const []))
            _Columna.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
      );
}

class _Columna {
  final String nombre;
  final String tipo;
  final bool pk;
  final bool fk;
  _Columna({
    required this.nombre,
    required this.tipo,
    required this.pk,
    required this.fk,
  });

  factory _Columna.fromJson(Map<String, dynamic> j) => _Columna(
        nombre: j['nombre']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? '',
        pk: j['pk'] == true,
        fk: j['fk'] == true,
      );
}

class _Relacion {
  final String desde;
  final String hasta;
  _Relacion({required this.desde, required this.hasta});

  factory _Relacion.fromJson(Map<String, dynamic> j) => _Relacion(
        desde: j['desde']?.toString() ?? '',
        hasta: j['hasta']?.toString() ?? '',
      );
}

class _EventoDb {
  final String modulo;
  final String mensaje;
  final DateTime hora;
  final List<String> tablas;
  _EventoDb({
    required this.modulo,
    required this.mensaje,
    required this.hora,
    required this.tablas,
  });
}

/// Dibuja las aristas FK como curvas entre el borde derecho del nodo origen y
/// el borde izquierdo del nodo destino (o invertido si el destino está a la
/// izquierda).
///
/// Con actividad reciente las aristas se iluminan y un PULSO viaja por la curva
/// ([fase] 0→1), de modo que la línea también "trabaja" en pantalla y no solo
/// el registro de texto.
class _AristasPainter extends CustomPainter {
  final List<_Relacion> relaciones;
  final Map<String, Offset> posiciones;
  final Map<String, Size> tamanos;
  final Set<String> resaltadas;
  final double fase;

  _AristasPainter({
    required this.relaciones,
    required this.posiciones,
    required this.tamanos,
    required this.resaltadas,
    required this.fase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in relaciones) {
      final a = posiciones[r.desde];
      final b = posiciones[r.hasta];
      if (a == null || b == null) continue;
      final sa = tamanos[r.desde] ?? const Size(200, 100);
      final sb = tamanos[r.hasta] ?? const Size(200, 100);

      final activa =
          resaltadas.contains(r.desde) || resaltadas.contains(r.hasta);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = activa ? 2.0 : 1.1
        ..color = activa ? const Color(0xAA34D399) : const Color(0x553B82F6);

      final centroA = a + Offset(sa.width / 2, sa.height / 2);
      final centroB = b + Offset(sb.width / 2, sb.height / 2);
      final bDerecha = centroB.dx >= centroA.dx;

      final p1 = Offset(
        bDerecha ? a.dx + sa.width : a.dx,
        centroA.dy,
      );
      final p2 = Offset(
        bDerecha ? b.dx : b.dx + sb.width,
        centroB.dy,
      );
      final dx = (p2.dx - p1.dx).abs() * 0.5 + 30;
      final c1 = Offset(p1.dx + (bDerecha ? dx : -dx), p1.dy);
      final c2 = Offset(p2.dx + (bDerecha ? -dx : dx), p2.dy);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);

      // Pulso viajero: un segmento brillante que recorre la curva.
      if (activa) {
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF6EE7B7);
        for (final metric in path.computeMetrics()) {
          final len = metric.length;
          if (len <= 0) continue;
          final seg = math.min(46.0, len * 0.35);
          final recorrido = (fase * (len + seg)) % (len + seg);
          final s = (recorrido - seg).clamp(0.0, len);
          final e = recorrido.clamp(0.0, len);
          if (e > s) canvas.drawPath(metric.extractPath(s, e), glow);
        }
      }

      // Marcas de cardinalidad (círculo en el extremo hijo).
      canvas.drawCircle(
        p1,
        2.6,
        Paint()
          ..color = activa ? const Color(0xFF34D399) : const Color(0x883B82F6),
      );
      canvas.drawCircle(
        p2,
        2.0,
        Paint()
          ..color = activa ? const Color(0xFF34D399) : const Color(0x553B82F6),
      );
    }
  }

  // `posiciones` y `resaltadas` se mutan en el mismo Map/Set, por lo que una
  // comparación por referencia o por longitud siempre daría `false` y las
  // aristas no se redibujarían al arrastrar un nodo, al cambiar el resaltado o
  // al avanzar el pulso. El diagrama es pequeño: repintar siempre es correcto
  // y barato (y solo ocurre mientras el pulso está activo).
  @override
  bool shouldRepaint(covariant _AristasPainter old) => true;
}
