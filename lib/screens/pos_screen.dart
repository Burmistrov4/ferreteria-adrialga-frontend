import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente_model.dart';
import '../models/producto_model.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _cargarTasaCambio();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        ? 'Tasa BCV: ${_tasaCambio.toStringAsFixed(2)} Bs'
                        : 'Tasa BCV: Sin conexión',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _tasaEsBCV ? null : Colors.orange.shade800,
                    ),
                  ),
                  if (!_tasaEsBCV)
                    const Text(
                      'Usando valor de respaldo',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
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
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _filtrarProductos,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por Nombre o Código SKU...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          prod.nombre,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'SKU: ${prod.skuCodigo}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '\$${prod.precioVenta.toStringAsFixed(2)}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: prod.stockActual > 0
                                                    ? Colors.blue.shade50
                                                    : Colors.red.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Stock: ${prod.stockActual}',
                                                style: const TextStyle(
                                                  fontSize: 10,
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
                          ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _clienteSeleccionado.nombreRazonSocial,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_clienteSeleccionado.tipoDocumento}-${_clienteSeleccionado.numDocumento}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                // Datos de contacto completos del cliente
                                // seleccionado (cargados desde la BD al
                                // elegirlo en el buscador del diálogo).
                                if (_clienteSeleccionado.direccion != null &&
                                    _clienteSeleccionado.direccion!.isNotEmpty)
                                  Text(
                                    _clienteSeleccionado.direccion!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (_clienteSeleccionado.telefono != null &&
                                    _clienteSeleccionado.telefono!.isNotEmpty)
                                  Text(
                                    'Tel: ${_clienteSeleccionado.telefono}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
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
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Carrito de Compras',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _carrito.length,
                      itemBuilder: (context, index) {
                        final item = _carrito[index];
                        return _CartItemTile(
                          key: ValueKey(item.producto.productoId),
                          item: item,
                          onQuantityChanged: (qty) =>
                              _actualizarCantidadManual(item, qty),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text('\$${_subtotalTotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('IVA (16%):'),
                      Text('\$${_ivaTotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL USD:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$${_totalPagar.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL VES:',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      Text(
                        'Bs. ${(_totalPagar * _tasaCambio).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text(
                        'COBRAR Y FACTURAR',
                        style: TextStyle(fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _carrito.isEmpty ? null : _iniciarProcesoVenta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatefulWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;

  const _CartItemTile({
    super.key,
    required this.item,
    required this.onQuantityChanged,
  });

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.cantidad.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
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
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      widget.onQuantityChanged(widget.item.cantidad - 1),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 46,
                  height: 32,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
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
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      widget.onQuantityChanged(widget.item.cantidad + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
