import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente_model.dart';
import '../models/factura_model.dart';
import '../models/producto_model.dart';
import '../services/api_service.dart';
import '../services/impresion_service.dart';
import '../services/shortcut_service.dart';
import '../widgets/cliente_dialog.dart';
import '../widgets/cobro_dialog.dart';

class CartItem {
  final ProductoModel producto;
  int cantidad;

  CartItem({required this.producto, this.cantidad = 1});

  double get subtotal => producto.precioVenta * cantidad;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<ProductoModel> _productos = [];
  List<ProductoModel> _filteredProductos = [];
  final List<CartItem> _carrito = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  ClienteModel _clienteSeleccionado = ClienteModel.consumidorFinal();
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
    _cargarProductos();
    _cargarTasaCambio();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_manejarTecla);
    _busquedaFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final productos = await ApiService.getProductos();
      if (mounted) {
        setState(() {
          _productos = productos;
          _filteredProductos = productos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _mostrarSnackBar('Error cargando productos: $e');
      }
    }
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

  void _filtrarProductos(String query) {
    setState(() {
      _filteredProductos = _productos
          .where(
            (p) =>
                p.nombre.toLowerCase().contains(query.toLowerCase()) ||
                p.skuCodigo.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    });
  }

  void _agregarAlCarrito(ProductoModel prod) {
    setState(() {
      final index = _carrito.indexWhere(
        (item) => item.producto.productoId == prod.productoId,
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
  }

  void _actualizarCantidadManual(CartItem item, int nuevaCantidad) {
    setState(() {
      if (nuevaCantidad > item.producto.stockActual) {
        item.cantidad = item.producto.stockActual;
        _mostrarSnackBar(
          'Ajustado al stock máximo disponible (${item.producto.stockActual})',
        );
      } else if (nuevaCantidad <= 0) {
        _carrito.remove(item);
      } else {
        item.cantidad = nuevaCantidad;
      }
    });
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
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  double get _subtotalTotal =>
      _carrito.fold(0, (sum, item) => sum + item.subtotal);
  double get _ivaTotal => _subtotalTotal * 0.16;
  double get _totalPagar => _subtotalTotal + _ivaTotal;

  Future<void> _iniciarProcesoVenta() async {
    if (_carrito.isEmpty) return;

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
        "Cliente_ID": _clienteSeleccionado.clienteId ?? 1,
        "Tipo_Pago": "Multipago",
        "Tasa_Cambio": resultadoPago['tasaCambio'],
        "Detalles_Pago": resultadoPago['detallesPago'],
        "Vuelto_USD": resultadoPago['vueltoUSD'],
        "Vuelto_VES": resultadoPago['vueltoVES'],
        "Detalles": _carrito
            .map(
              (item) => {
                "Producto_ID": item.producto.productoId,
                "Cantidad": item.cantidad,
                "Precio_Unitario": item.producto.precioVenta,
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
            _clienteSeleccionado = ClienteModel.consumidorFinal();
          });
          _cargarProductos();
        } else {
          _mostrarSnackBar('Error procesando venta: ${result['error']}');
        }
      }
    }
  }

  // ─── Piezas reutilizables del layout ───────────────────────────────────────

  Widget _buildBarraBusqueda() {
    return TextField(
      controller: _searchController,
      focusNode: _busquedaFocus,
      onChanged: _filtrarProductos,
      decoration: const InputDecoration(
        labelText: 'Buscar por Nombre o Código SKU...',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
      ),
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
            itemCount: _filteredProductos.length,
            itemBuilder: (context, index) {
              final prod = _filteredProductos[index];
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Stock: ${prod.stockActual}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: prod.stockActual > 0
                                      ? Theme.of(context).colorScheme.onPrimaryContainer
                                      : Theme.of(context).colorScheme.onErrorContainer,
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
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Icon(Icons.person, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _clienteSeleccionado.nombreRazonSocial,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_clienteSeleccionado.tipoDocumento}-${_clienteSeleccionado.numDocumento}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  if (_clienteSeleccionado.direccion != null &&
                      _clienteSeleccionado.direccion!.isNotEmpty)
                    Text(
                      _clienteSeleccionado.direccion!,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_clienteSeleccionado.telefono != null &&
                      _clienteSeleccionado.telefono!.isNotEmpty)
                    Text(
                      'Tel: ${_clienteSeleccionado.telefono}',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _seleccionarCliente,
              child: const Text('CAMBIAR'),
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
    return ListView.builder(
      itemCount: _carrito.length,
      itemBuilder: (context, index) {
        final item = _carrito[index];
        return _CartItemTile(
          key: ValueKey(item.producto.productoId),
          item: item,
          quantityFocus: _focosCantidad[index],
          activa: _indiceActivo == index,
          onActivar: () => setState(() => _indiceActivo = index),
          onQuantityChanged: (qty) => _actualizarCantidadManual(item, qty),
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
        const Text('Carrito de Compras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            const Text('TOTAL USD:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '\$${_totalPagar.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary),
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.tertiary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.point_of_sale),
            label: const Text('COBRAR Y FACTURAR', style: TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: _carrito.isEmpty ? null : (onCobrar ?? _iniciarProcesoVenta),
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
          title: const Text('Punto de Venta (POS) - Adrialga'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tasaEsBCV
                          ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(4)} Bs'
                          : 'Tasa BCV: Sin conexión',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _tasaEsBCV
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (!_tasaEsBCV)
                      Text(
                        'Usando valor de respaldo',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
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
            return esEscritorio ? _planoEscritorio(context) : _planoMovil(context);
          },
        ),
      ),
    );
  }
}

class _CartItemTile extends StatefulWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final FocusNode quantityFocus;
  final bool activa;
  final VoidCallback onActivar;

  const _CartItemTile({
    super.key,
    required this.item,
    required this.quantityFocus,
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: widget.activa
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : null,
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
                      widget.item.producto.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '\$${widget.item.producto.precioVenta.toStringAsFixed(2)} c/u = \$${widget.item.subtotal.toStringAsFixed(2)}',
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
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 24),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    // No bajar de 1 con el botón (evita borrados accidentales).
                    onPressed: widget.item.cantidad <= 1
                        ? null
                        : () =>
                            widget.onQuantityChanged(widget.item.cantidad - 1),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 46,
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
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 24),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () =>
                        widget.onQuantityChanged(widget.item.cantidad + 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}