import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente_model.dart';
import '../models/factura_model.dart';
import '../models/producto_model.dart';
import '../models/variante_model.dart';
import '../services/api_service.dart';
import '../services/impresion_service.dart';
import '../services/session_guard.dart';
import '../services/shortcut_service.dart';
import '../services/socket_service.dart';
import '../utils/responsive.dart';
import '../widgets/cliente_dialog.dart';
import '../widgets/cobro_dialog.dart';
import '../widgets/walkthrough_overlay.dart';

class CartItem {
  final ProductoModel producto;

  /// Variante exacta vendida (null = producto lineal). Aplica precio/stock
  /// propios de la combinación: la transacción registra el SKU variante.
  final ProductoVariante? variante;
  int cantidad;

  CartItem({required this.producto, this.variante, this.cantidad = 1});

  /// Precio cobrado: el de la variante si existe, si no el del producto.
  double get precioVentaEfectivo => variante?.precio ?? producto.precioVenta;

  double get subtotal => precioVentaEfectivo * cantidad;

  /// Nombre para el carrito/ticket: "Lámpara LED · Color: Gris".
  String get nombreMostrado {
    if (variante == null || variante!.atributos.isEmpty) {
      return producto.nombre;
    }
    final attrs = variante!.atributos.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return '${producto.nombre} ($attrs)';
  }
}

/// Clave estable y única de una línea de carrito: combina el ID de producto
/// con el ID de variante (o 'base' para productos lineales). Evita la
/// colisión de claves cuando dos variantes del mismo producto conviven en el
/// carrito, que provocaba que Flutter reusara el State de la fila y los
/// botones +/- operaran sobre el ítem equivocado.
String _cartLineKey(CartItem item) =>
    '${item.producto.productoId}-${item.variante?.varianteId ?? 'base'}';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<ProductoModel> _filteredProductos = [];
  final Map<int, ProductoModel> _productosCache = {};
  Timer? _debounceBusqueda;
  DateTime? _ultimaActualizacionProductos;
  int _busquedaSecuencia = 0;
  final List<CartItem> _carrito = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  /// Filtro de catálogo: todos, con stock o agotados.
  /// El POS sigue validando stock en el momento de agregar y cobrar.
  String _filtroStock = 'todos';

  List<ProductoModel> get _productosVisibles {
    if (_filtroStock == 'con') {
      return _filteredProductos.where((p) => p.stockActual > 0).toList();
    }
    if (_filtroStock == 'sin') {
      return _filteredProductos.where((p) => p.stockActual <= 0).toList();
    }
    return _filteredProductos;
  }

  /// Cliente de la venta en curso: initia en null para forzar una
  /// asignación explícita. El checkbox "Consumidor Final" habilita el cobro
  /// sin seleccionar un cliente registrado (resuelto al registro real
  /// V-00000000 del backend, nunca a un ID hardcodeado).
  ClienteModel? _clienteSeleccionado;
  bool _esConsumidorFinal = false;
  ClienteModel? _cacheConsumidorFinal;
  double _tasaCambio = 36.50;
  bool _tasaEsBCV = false;

  // ── Shorcutos mouseless (Ferretería): F2 buscador · F3 cantidad · F12 cobro ──
  final FocusNode _busquedaFocus = FocusNode();
  final List<FocusNode> _focosCantidad = [];
  int? _indiceActivo;

  bool _manejarTecla(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f2) {
      _busquedaFocus.requestFocus();
      return true;
    }
    if (k == LogicalKeyboardKey.f3) {
      _enfocarCantidadActiva();
      return true;
    }
    if (k == LogicalKeyboardKey.f12) {
      if (_carrito.isNotEmpty) _iniciarProcesoVenta();
      return true;
    }
    return false;
  }

  void _enfocarCantidadActiva() {
    if (_carrito.isEmpty) return;
    final idx = (_indiceActivo != null && _indiceActivo! < _carrito.length)
        ? _indiceActivo!
        : 0;
    if (idx < _focosCantidad.length) _focosCantidad[idx].requestFocus();
  }

  // Breakpoint oficial de AGENTS.md: Desktop/POS > 900dp con carrito persistente.
  static const double _breakpointDesktop = 900.0;

  @override
  void initState() {
    super.initState();
    ShortcutService.setModule('pos');
    HardwareKeyboard.instance.addHandler(_manejarTecla);
    // WebSocket LAN: POS solo reacciona a cambios que pueden alterar su
    // catálogo/stock. Antes escuchaba TODOS los db_update.
    SocketService.onDbUpdateModulo(_alRecibirDbUpdate);
    _cargarProductos();
    _cargarTasaCambio();
    // FASE C: tutorial CONTEXTUAL de cobro, sólo la primera vez que este rol
    // entra al POS. Post-frame: el Overlay raíz aún no existe en initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WalkthroughPrefs.mostrarSiAplica(
        context,
        modulo: 'pos',
        pasos: walkthroughPos(),
      );
    });
  }

  void _alRecibirDbUpdate(String modulo) {
    // Guardia de ciclo de vida: el socket puede llegar justo tras el
    // desmontaje.
    if (!mounted) return;
    if (modulo == 'tasa') {
      _cargarTasaCambio();
      return;
    }
    if (modulo != 'ventas' &&
        modulo != 'inventario' &&
        modulo != 'categorias' &&
        modulo != 'configuracion' &&
        modulo != '__reconexion__')
      return;
    // Invalidar caché de variantes: ventas/inventario pueden haber cambiado
    // stock o precio en otro terminal de la LAN. Categorías/configuración
    // también afectan los datos visibles del catálogo y las reglas del POS.
    _matricesCache.clear();
    _ultimaActualizacionProductos = DateTime.now();
    _cargarProductos();
  }

  // ── Higiene de FocusNode del listado (crash "used after being disposed") ──
  //
  // Regla: un FocusNode JAMÁS se dispone en el mismo frame en que su tile
  // sigue montado (el dispose() del TextField lo usa para desacoplarse y el
  // framework lanza la aserción). Toda eliminación difiere el dispose al
  // callback post-frame, cuando el ListView ya reconstruyó sin ese ítem.
  final List<FocusNode> _focosPendientesDispose = [];
  bool _flushDisposeProgramado = false;

  void _disponerFocoPostFrame(FocusNode nodo) {
    _focosPendientesDispose.add(nodo);
    if (_flushDisposeProgramado) return;
    _flushDisposeProgramado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushDisposeProgramado = false;
      final pendientes = List.of(_focosPendientesDispose);
      _focosPendientesDispose.clear();
      for (final n in pendientes) {
        // El nodo pudo quedar en blanco tras un clear() total; solo se
        // dispone si aún no fue recolectado por dispose() de la pantalla.
        n.dispose();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_manejarTecla);
    SocketService.offDbUpdateModulo(_alRecibirDbUpdate);
    _debounceBusqueda?.cancel();
    _busquedaFocus.dispose();
    _searchController.dispose();
    // Recolectar todos los FocusNode del carrito (activos y los pendientes
    // de dispose diferido) evita el crash "A FocusNode was used after being
    // disposed" al cerrar la vista o purgar el carrito.
    for (final f in _focosCantidad) {
      f.dispose();
    }
    _focosCantidad.clear();
    for (final f in _focosPendientesDispose) {
      f.dispose();
    }
    _focosPendientesDispose.clear();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final q = _searchController.text.trim();
      final pagina = await ApiService.getProductosPaginados(
        limit: 50,
        q: q.isEmpty ? null : q,
        conStock: _filtroStock == 'con',
        sinStock: _filtroStock == 'sin',
      );
      if (mounted) {
        setState(() {
          _filteredProductos = pagina.datos;
          for (final producto in pagina.datos) {
            _productosCache[producto.productoId] = producto;
          }
          _isLoading = false;
        });
        _ofrecerRestaurarCarrito();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _mostrarSnackBar('Error cargando productos: $e');
      }
    }
  }

  void _filtrarProductos(String query) {
    final secuencia = ++_busquedaSecuencia;
    _debounceBusqueda?.cancel();
    _debounceBusqueda = Timer(const Duration(milliseconds: 250), () async {
      try {
        final q = query.trim();
        final pagina = await ApiService.getProductosPaginados(
          limit: 50,
          q: q.isEmpty ? null : q,
          conStock: _filtroStock == 'con',
          sinStock: _filtroStock == 'sin',
        );
        if (!mounted || secuencia != _busquedaSecuencia) return;
        setState(() {
          _filteredProductos = pagina.datos;
          for (final producto in pagina.datos) {
            _productosCache[producto.productoId] = producto;
          }
        });
      } catch (e) {
        if (!mounted || secuencia != _busquedaSecuencia) return;
        _mostrarSnackBar('Error buscando productos: $e');
      }
    });
  }

  Future<void> _cargarTasaCambio() async {
    final tasa = await ApiService.getTasaCambio();
    if (mounted) {
      setState(() {
        _tasaCambio = tasa;
        _tasaEsBCV = ApiService.lastTasaEsBCV;
      });
    }
  }

  /// Sincroniza el snapshot global del carrito para el guardia de sesión
  /// (respaldo automático si el JWT expira a mitad de una venta).
  void _sincronizarRespaldoCarrito() {
    SessionGuard.carritoActual = _carrito
        // Ítems de matriz no se respaldan: su stock/precio pudo cambiar tras
        // cortes de sesión y exige re-selección (regla de seguridad).
        .where((i) => i.variante == null)
        .map((i) => {'producto': i.producto.toJson(), 'cantidad': i.cantidad})
        .toList();
  }

  /// Si existe un carrito respaldado (por una sesión que expiró a mitad de
  /// venta), pregunta al cajero si desea restaurarlo. Si suelta o acepta,
  /// la copia en SharedPreferences se elimina para no volver a preguntar.
  Future<void> _ofrecerRestaurarCarrito() async {
    final respaldo = await SessionGuard.leerRespaldoCarrito();
    if (respaldo == null || !mounted) return;
    await SessionGuard.limpiarRespaldoCarrito();
    // Solo se ofrecen ítems cuyo producto sigue existiendo y tiene stock,
    // limitados al stock actual (el inventario pudo cambiar entre sesiones).
    final restaurables = <CartItem>[];
    for (final entrada in respaldo) {
      try {
        final prod = ProductoModel.fromJson(
          (entrada['producto'] as Map).cast<String, dynamic>(),
        );
        ProductoModel? vivo = _productosCache[prod.productoId];
        if (vivo == null) {
          vivo = await ApiService.getProductoById(prod.productoId);
        }
        if (vivo != null) _productosCache[vivo.productoId] = vivo;
        final cant = ((entrada['cantidad'] as num?)?.toInt() ?? 1).clamp(
          1,
          1 << 30,
        );
        if (vivo != null && vivo.stockActual > 0) {
          restaurables.add(
            CartItem(
              producto: vivo,
              cantidad: cant > vivo.stockActual ? vivo.stockActual : cant,
            ),
          );
        }
      } catch (_) {
        // Entrada corrupta: simplemente se omite.
      }
    }
    if (restaurables.isEmpty || !mounted) return;
    final restaurar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carrito recuperado'),
        content: Text(
          'La sesión anterior expiró con ${restaurables.length} producto(s) sin cobrar. ¿Deseas restaurar ese carrito?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Empezar de cero'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar carrito'),
          ),
        ],
      ),
    );
    if (restaurar == true && mounted) {
      setState(() {
        // Los FocusNode de cantidad se ajustan solos en el build siguiente.
        _carrito.addAll(restaurables);
      });
      _sincronizarRespaldoCarrito();
    }
  }

  /// Caché de matrices por producto (un GET por producto por sesión del POS).
  final Map<int, MatrizVariantes> _matricesCache = {};

  void _agregarAlCarrito(ProductoModel prod) async {
    // Productos matriciales: si tiene más de una variante (o atributos),
    // se abre el selector de combinación antes de tocar el carrito.
    try {
      final matriz = _matricesCache[prod.productoId] ??=
          MatrizVariantes.fromJson(
            await ApiService.getVariantesProducto(prod.productoId),
          );
      // Solo se interviene cuando hay matriz REAL (2+ variantes o atributos):
      // la variante "por defecto" del backfill se trata como venta lineal.
      final combinatorias = matriz.matriz
          .where((v) => v.atributos.isNotEmpty || matriz.matriz.length > 1)
          .toList();
      if (matriz.ejes.isNotEmpty && combinatorias.length > 1) {
        final elegida = await _seleccionarVariante(prod, combinatorias);
        if (elegida == null) return;
        _agregarVarianteAlCarrito(prod, elegida);
        return;
      }
    } catch (_) {
      // Sin matriz consultable (sin conexión puntual): continuar lineal.
    }
    _agregarLineal(prod);
  }

  void _agregarLineal(ProductoModel prod) {
    setState(() {
      final index = _carrito.indexWhere(
        (item) =>
            item.producto.productoId == prod.productoId &&
            item.variante == null,
      );
      if (index >= 0) {
        if (_carrito[index].cantidad < prod.stockActual) {
          _carrito[index].cantidad++;
        } else {
          _mostrarSnackBar(
            'Stock máximo alcanzado (${prod.stockActual} unidades)',
          );
        }
      } else {
        if (prod.stockActual > 0) {
          _carrito.add(CartItem(producto: prod, cantidad: 1));
        } else {
          _mostrarSnackBar('Producto sin stock disponible');
        }
      }
    });
    _sincronizarRespaldoCarrito();
  }

  void _agregarVarianteAlCarrito(ProductoModel prod, ProductoVariante v) {
    setState(() {
      final index = _carrito.indexWhere(
        (item) => item.variante?.varianteId == v.varianteId,
      );
      if (index >= 0) {
        if (_carrito[index].cantidad < v.stock) {
          _carrito[index].cantidad++;
        } else {
          _mostrarSnackBar('Stock máximo de la combinación (${v.stock})');
        }
      } else if (v.stock > 0) {
        _carrito.add(CartItem(producto: prod, variante: v, cantidad: 1));
      } else {
        _mostrarSnackBar('Combinación sin stock disponible');
      }
    });
    _sincronizarRespaldoCarrito();
  }

  /// Selector de variante optimizado para móvil: hoja inferior
  /// (showModalBottomSheet) con ListTile por combinación. El onTap cierra la
  /// hoja devolviendo la variante elegida al carrito. Reemplaza el antiguo
  /// AlertDialog+ChoiceChip, que era tosco y difícil de tocar en pantallas
  /// pequeñas (el ChoiceChip absorbía el gesto de selección).
  Future<ProductoVariante?> _seleccionarVariante(
    ProductoModel prod,
    List<ProductoVariante> opciones,
  ) {
    return showModalBottomSheet<ProductoVariante>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'Elige una variante — ${prod.nombre}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: opciones.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final v = opciones[i];
                      final attrs = v.atributos.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join(' · ');
                      final etiqueta = attrs.isEmpty ? v.sku : attrs;
                      final agotada = v.stock <= 0;
                      return ListTile(
                        leading: Icon(
                          agotada ? Icons.block : Icons.check_circle_outline,
                          color: agotada ? cs.error : cs.primary,
                        ),
                        title: Text(
                          etiqueta,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          agotada ? 'Sin stock' : 'Stock: ${v.stock}',
                          style: TextStyle(
                            fontSize: 12,
                            color: agotada ? cs.error : cs.onSurfaceVariant,
                          ),
                        ),
                        trailing: agotada
                            ? const Icon(Icons.lock_outline, size: 18)
                            : const Icon(Icons.chevron_right),
                        // onTap fluido: cierra la hoja y pasa la variante.
                        enabled: !agotada,
                        onTap: agotada
                            ? null
                            : () => Navigator.pop(sheetCtx, v),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _actualizarCantidadManual(CartItem item, int nuevaCantidad) {
    final stockLimite = item.variante?.stock ?? item.producto.stockActual;
    setState(() {
      if (nuevaCantidad > stockLimite) {
        item.cantidad = stockLimite;
        _mostrarSnackBar(
          'Ajustado al stock máximo de la combinación ($stockLimite)',
        );
      } else if (nuevaCantidad <= 0) {
        _retirarItemDelCarrito(item);
      } else {
        item.cantidad = nuevaCantidad;
      }
    });
    _sincronizarRespaldoCarrito();
  }

  /// Lógica compartida de retiro (papelera, X, Dismissible o cantidad=0):
  /// saca el ítem, recorta su FocusNode de la lista y reacomoda el índice
  /// activo del atajo F3. El nodo se dispone al FINAL del frame: si se
  /// dispusiera de inmediato, el tile montado en este frame lo tocaría al
  /// desacoplarse y se dispararía "A FocusNode was used after being disposed".
  /// Debe llamarse SIEMPRE dentro de un setState.
  void _retirarItemDelCarrito(CartItem item) {
    final idx = _carrito.indexOf(item);
    _carrito.remove(item);
    if (idx >= 0 && idx < _focosCantidad.length) {
      _disponerFocoPostFrame(_focosCantidad.removeAt(idx));
    }
    if (_indiceActivo != null) {
      if (_carrito.isEmpty) {
        _indiceActivo = null;
      } else if (_indiceActivo! >= _carrito.length) {
        _indiceActivo = _carrito.length - 1;
      }
    }
  }

  /// Elimina un ítem del carrito (botón papelera, X o Dismissible).
  void _eliminarDelCarrito(CartItem item) {
    setState(() => _retirarItemDelCarrito(item));
    _sincronizarRespaldoCarrito();
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => const ClienteDialog(),
    );

    if (cliente != null && mounted) {
      setState(() => _clienteSeleccionado = cliente);
    }
  }

  void _mostrarSnackBar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        // 4s: los avisos de ajuste de stock (p. ej. "Ajustado al stock
        // máximo") requieren tiempo de lectura; 2s era insuficiente en PC.
        // showCloseIcon permite cerrarlo antes si el cajero ya lo leyó.
        duration: const Duration(seconds: 4),
        showCloseIcon: true,
      ),
    );
  }

  double get _subtotalTotal =>
      _carrito.fold(0, (sum, item) => sum + item.subtotal);
  double get _ivaTotal => _subtotalTotal * 0.16;
  double get _totalPagar => _subtotalTotal + _ivaTotal;

  /// Resuelve el registro real del "Consumidor Final" (V-00000000) en el
  /// backend y lo memoriza. Devuelve null si no hay conexión/no existe.
  Future<ClienteModel?> _obtenerConsumidorFinal() async {
    if (_cacheConsumidorFinal != null) return _cacheConsumidorFinal;
    _cacheConsumidorFinal = await ApiService.buscarClientePorDocumento(
      'V-00000000',
    );
    // Si el backend no reporta el registro (aún sin seed), usa el modelo
    // estático como última red de seguridad con su ID conocido.
    return _cacheConsumidorFinal ?? ClienteModel.consumidorFinal();
  }

  /// Validación previa del cobro: hay cliente asignado o el checkbox explícito
  /// de Consumidor Final está marcado.
  bool get _puedeCobrar =>
      _carrito.isNotEmpty &&
      (_clienteSeleccionado != null || _esConsumidorFinal);

  Future<void> _iniciarProcesoVenta() async {
    if (!_puedeCobrar) return;

    // Resolución del cliente efectivo: asignado explícitamente o el
    // registro real de Consumidor Final rescatado del backend.
    final ClienteModel cliente =
        _clienteSeleccionado ??
        (await _obtenerConsumidorFinal()) ??
        ClienteModel.consumidorFinal();
    if (!mounted) return;

    final resultadoPago = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CobroDialog(
        totalUSD: _totalPagar,
        tasaCambio: _tasaCambio,
        tasaEsBCV: _tasaEsBCV,
      ),
    );

    if (resultadoPago != null) {
      final facturaData = {
        "Cliente_ID": cliente.clienteId,
        "Tipo_Pago": "Multipago",
        "Tasa_Cambio": resultadoPago['tasaCambio'],
        "Detalles_Pago": resultadoPago['detallesPago'],
        "Vuelto_USD": resultadoPago['vueltoUSD'],
        "Vuelto_VES": resultadoPago['vueltoVES'],
        "Detalles": _carrito
            .map(
              (item) => {
                "Producto_ID": item.producto.productoId,
                if (item.variante != null)
                  "Variante_ID": item.variante!.varianteId,
                "Cantidad": item.cantidad,
                "Precio_Unitario": item.precioVentaEfectivo,
              },
            )
            .toList(),
      };

      final result = await ApiService.createFactura(facturaData);

      if (mounted) {
        if (result['success'] == true) {
          _mostrarSnackBar('¡Venta procesada con éxito!');
          // Auto-impresión del ticket térmico (si el cajero lo marcó).
          if (resultadoPago['imprimirTicket'] == true &&
              result['factura'] is Map) {
            try {
              final fm = FacturaModel.fromJson(
                (result['factura'] as Map).cast<String, dynamic>(),
              );
              await ImpresionService.imprimirTicketFactura(fm);
            } catch (_) {
              // La impresión no debe bloquear la venta ya confirmada.
            }
          }
          setState(() {
            _carrito.clear();
            _clienteSeleccionado = null;
            _esConsumidorFinal = false;
            _indiceActivo = null;
          });
          _sincronizarRespaldoCarrito();
          // El backend emite `db_update: ventas` antes de responder. Si el
          // WebSocket ya actualizó el catálogo, no repetir la misma consulta;
          // si no llegó el evento (socket caído), mantener un fallback local.
          final ultima = _ultimaActualizacionProductos;
          if (ultima == null ||
              DateTime.now().difference(ultima) >
                  const Duration(milliseconds: 800)) {
            _cargarProductos();
          }
        } else {
          _mostrarSnackBar('Error procesando venta: ${result['error']}');
        }
      }
    }
  }

  // ─── Piezas reutilizables del layout ───────────────────────────────────────

  Widget _buildBarraBusqueda() {
return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _busquedaFocus,
            onChanged: _filtrarProductos,
            decoration: const InputDecoration(
              labelText: 'Buscar por Nombre o Código SKU...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 155,
          child: DropdownButtonFormField<String>(
            initialValue: _filtroStock,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Existencias',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(value: 'con', child: Text('Con stock')),
              DropdownMenuItem(value: 'sin', child: Text('Sin stock')),
            ],
            onChanged: (valor) {
              if (valor == null || !mounted) return;
              setState(() => _filtroStock = valor);
              _cargarProductos();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogo() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 145,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _productosVisibles.length,
            itemBuilder: (context, index) {
              final prod = _productosVisibles[index];
              return Card(
                elevation: 2,
                child: InkWell(
                  onTap: () => _agregarAlCarrito(prod),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          prod.nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'SKU: ${prod.skuCodigo}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                '\$${prod.precioVenta.toStringAsFixed(2)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: prod.stockActual > 0
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Stock: ${prod.stockActual}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: prod.stockActual > 0
                                      ? Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer
                                      : Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildClienteCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cliente = _clienteSeleccionado;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  cliente != null ? Icons.person : Icons.person_search,
                  color: cliente != null ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: cliente == null
                      ? Text(
                          'Sin cliente asignado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.error,
                            fontSize: 13,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cliente.nombreRazonSocial,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${cliente.tipoDocumento}-${cliente.numDocumento}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (cliente.direccion != null &&
                                cliente.direccion!.isNotEmpty)
                              Text(
                                cliente.direccion!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (cliente.telefono != null &&
                                cliente.telefono!.isNotEmpty)
                              Text(
                                'Tel: ${cliente.telefono}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _seleccionarCliente,
                  child: Text(cliente == null ? 'Asignar' : 'CAMBIAR'),
                ),
              ],
            ),
            // Checkbox explícito: permite cobrar sin cliente nombrado, pero
            // nunca con un fallback implícito.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  setState(() => _esConsumidorFinal = !_esConsumidorFinal),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Checkbox(
                      value: _esConsumidorFinal,
                      onChanged: (v) =>
                          setState(() => _esConsumidorFinal = v ?? false),
                    ),
                    Expanded(
                      child: Text(
                        'Venta sin cliente (Consumidor Final)',
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarritoLista() {
    // Mantener un FocusNode por ítem para el atajo F3 (cantidad).
    while (_focosCantidad.length < _carrito.length) {
      _focosCantidad.add(FocusNode());
    }
    // Recorte simétrico (p. ej. tras vaciar el carrito al cobrar): los nodos
    // excedentes se disponen al final del frame, cuando su tile ya se
    // desmontó con el rebuild. Sin este recorte la lista quedaba más larga
    // que el carrito y un removeAt(idx) posterior disponía un nodo EN USO.
    while (_focosCantidad.length > _carrito.length) {
      _disponerFocoPostFrame(_focosCantidad.removeLast());
    }
    return ListView.builder(
      itemCount: _carrito.length,
      itemBuilder: (context, index) {
        final item = _carrito[index];
        return _CartItemTile(
          // Clave compuesta producto+variante: dos variantes del MISMO
          // producto (ej. Azul/Gris de "Lámpara Matriz E2E") tenían la
          // misma key (solo productoId) y Flutter reusaba el State,
          // haciendo que los botones +/- operaran sobre el ítem equivocado.
          key: ValueKey(_cartLineKey(item)),
          item: item,
          quantityFocus: _focosCantidad[index],
          activa: _indiceActivo == index,
          onActivar: () => setState(() => _indiceActivo = index),
          onQuantityChanged: (qty) => _actualizarCantidadManual(item, qty),
          onEliminar: () => _eliminarDelCarrito(item),
        );
      },
    );
  }

  Widget _filaTotal(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(valor)],
      ),
    );
  }

  /// Panel del carrito (cliente + ítems + totales + botón cobrar).
  /// En el layout de escritorio vive en una columna con altura acotada
  /// (Expanded); en el sheet móvil la lista de ítems recibe altura fija.
  Widget _buildPanelCarrito(
    BuildContext context, {
    bool enSheet = false,
    VoidCallback? onCobrar,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildClienteCard(context),
        const SizedBox(height: 8),
        const Text(
          'Carrito de Compras',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (enSheet)
          SizedBox(height: 220, child: _buildCarritoLista())
        else
          Expanded(child: _buildCarritoLista()),
        const Divider(),
        _filaTotal('Subtotal:', '\$${_subtotalTotal.toStringAsFixed(2)}'),
        _filaTotal('IVA (16%):', '\$${_ivaTotal.toStringAsFixed(2)}'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TOTAL USD:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '\$${_totalPagar.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TOTAL VES:',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            Text(
              'Bs. ${(_totalPagar * _tasaCambio).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cs.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.point_of_sale),
            label: const Text(
              'COBRAR Y FACTURAR',
              style: TextStyle(fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: !_puedeCobrar
                ? null
                : (onCobrar ?? _iniciarProcesoVenta),
          ),
        ),
        // Con el carrito cargado pero sin cliente, se orienta al cajero.
        if (_carrito.isNotEmpty &&
            _clienteSeleccionado == null &&
            !_esConsumidorFinal)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Asigna un cliente o marca "Consumidor Final" para cobrar.',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
      ],
    );
  }

  /// Layout de escritorio/POS: catálogo (izquierda) + carrito persistente (derecha).
  Widget _planoEscritorio(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildBarraBusqueda(),
                const SizedBox(height: 12),
                Expanded(child: _buildCatalogo()),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(left: BorderSide(color: cs.outlineVariant)),
            ),
            padding: const EdgeInsets.all(12.0),
            child: _buildPanelCarrito(context),
          ),
        ),
      ],
    );
  }

  /// Layout móvil: catálogo a pantalla completa + botón inferior que abre el
  /// carrito en un `showModalBottomSheet` adaptativo (cubre el teclado).
  Widget _planoMovil(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalItems = _carrito.fold<int>(0, (sum, it) => sum + it.cantidad);
    return Stack(
      children: [
        Padding(
          // Padding inferior suficiente para no tapar el botón "Ver Carrito".
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          child: Column(
            children: [
              _buildBarraBusqueda(),
              const SizedBox(height: 12),
              Expanded(child: _buildCatalogo()),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _carrito.isEmpty ? null : _verCarritoMovil,
                icon: const Icon(Icons.shopping_cart),
                label: Text(
                  _carrito.isEmpty
                      ? 'Carrito vacío'
                      : 'Ver Carrito ($totalItems ${totalItems == 1 ? 'ítem' : 'ítems'}) · \$${_totalPagar.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _verCarritoMovil() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) {
        final insets = MediaQuery.viewInsetsOf(sheetCtx);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: insets.bottom + 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildPanelCarrito(
                sheetCtx,
                enSheet: true,
                onCobrar: () async {
                  Navigator.pop(sheetCtx);
                  await _iniciarProcesoVenta();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            AdrialgaResponsive.isMobile(MediaQuery.sizeOf(context).width)
                ? 'POS · Adrialga'
                : 'Punto de Venta (POS) - Adrialga',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!AdrialgaResponsive.isMobile(MediaQuery.sizeOf(context).width))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 190),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _tasaEsBCV
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _tasaEsBCV
                          ? 'BCV ${_tasaCambio.toStringAsFixed(4)} Bs/\$'
                          : 'Tasa de respaldo ${_tasaCambio.toStringAsFixed(4)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _tasaEsBCV
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Actualizar productos y tasa',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _cargarProductos();
                _cargarTasaCambio();
              },
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final esEscritorio = constraints.maxWidth >= _breakpointDesktop;
            return esEscritorio
                ? _planoEscritorio(context)
                : _planoMovil(context);
          },
        ),
      ),
    );
  }
}

class _CartItemTile extends StatefulWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onEliminar;
  final FocusNode quantityFocus;
  final bool activa;
  final VoidCallback onActivar;

  const _CartItemTile({
    super.key,
    required this.item,
    required this.quantityFocus,
    required this.onEliminar,
    this.activa = false,
    required this.onActivar,
    required this.onQuantityChanged,
  });

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.cantidad.toString());
    widget.quantityFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!widget.quantityFocus.hasFocus) {
      if (_controller.text.isEmpty ||
          (int.tryParse(_controller.text) ?? 0) <= 0) {
        widget.onQuantityChanged(0);
      } else {
        _syncControllerText();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerText();
  }

  void _syncControllerText() {
    final currentVal = int.tryParse(_controller.text);
    if (currentVal != widget.item.cantidad) {
      _controller.text = widget.item.cantidad.toString();
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    widget.quantityFocus.removeListener(_onFocusChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Deslizar hacia la derecha elimina el ítem del carrito (gesto intuitivo).
    // El fondo rojo con papelera aparece durante el gesto.
    final tarjeta = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: widget.activa ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: widget.activa
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: widget.onActivar,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.nombreMostrado,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '\$${widget.item.precioVentaEfectivo.toStringAsFixed(2)} c/u = \$${widget.item.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // En cantidad 1, el botón − se transforma en papelera para
                  // eliminar el producto de forma explícita.
                  IconButton(
                    icon: Icon(
                      widget.item.cantidad <= 1
                          ? Icons.delete_outline
                          : Icons.remove_circle_outline,
                      size: 22,
                      color: widget.item.cantidad <= 1 ? cs.error : null,
                    ),
                    iconSize: 22,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: widget.item.cantidad <= 1
                        ? 'Eliminar del carrito'
                        : 'Disminuir cantidad',
                    onPressed: widget.item.cantidad <= 1
                        ? widget.onEliminar
                        : () => widget.onQuantityChanged(
                            widget.item.cantidad - 1,
                          ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 44,
                    height: 32,
                    child: TextField(
                      controller: _controller,
                      focusNode: widget.quantityFocus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty) {
                          final valInt = int.tryParse(val);
                          if (valInt != null) widget.onQuantityChanged(valInt);
                        }
                      },
                      onSubmitted: (val) {
                        final valInt = int.tryParse(val) ?? 0;
                        widget.onQuantityChanged(valInt);
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    iconSize: 22,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: 'Aumentar cantidad',
                    onPressed: () =>
                        widget.onQuantityChanged(widget.item.cantidad + 1),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    iconSize: 18,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    color: cs.onSurfaceVariant,
                    tooltip: 'Quitar producto',
                    onPressed: widget.onEliminar,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${_cartLineKey(widget.item)}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => widget.onEliminar(),
      child: tarjeta,
    );
  }
}
