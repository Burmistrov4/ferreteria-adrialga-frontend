import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../services/api_service.dart';
import '../services/shortcut_service.dart';

class EntradasScreen extends StatefulWidget {
  /// Producto a preseleccionar al abrir la pantalla (precarga de quiebre de stock).
  final int? productoInicialId;

  /// IDs de productos con quiebre para mostrarlos como chips de acceso rápido.
  final List<int>? idsBajoStock;

  const EntradasScreen({super.key, this.productoInicialId, this.idsBajoStock});

  @override
  State<EntradasScreen> createState() => _EntradasScreenState();
}

class _EntradasScreenState extends State<EntradasScreen> {
  List<ProductoModel> _productos = [];
  ProductoModel? _productoSeleccionado;
  final _cantidadController = TextEditingController();
  final _costoController = TextEditingController();
  bool _isLoading = false;

List<dynamic> _proveedores = [];
  dynamic _proveedorSeleccionado;
  bool _cargandoProveedores = true;
  String _formaPago = 'Contado'; // 'Contado' | 'Credito'

  List<int> _idsBajoStock = [];

  @override
  void initState() {
    super.initState();
    ShortcutService.setModule('entradas');
    _idsBajoStock = widget.idsBajoStock ?? const [];
    _cargarProductos();
    _cargarProveedores();
  }

  String _dosDigitos(int n) => n.toString().padLeft(2, '0');

  String _generarNumeroNota() {
    final now = DateTime.now();
    final ts = '${now.year}${_dosDigitos(now.month)}${_dosDigitos(now.day)}'
        '${_dosDigitos(now.hour)}${_dosDigitos(now.minute)}${_dosDigitos(now.second)}';
    return 'NE-$ts';
  }

  Future<void> _cargarProveedores() async {
    setState(() => _cargandoProveedores = true);
    try {
      final provs = await ApiService.getProveedores();
      if (mounted) {
        setState(() {
          _proveedores = provs;
          _cargandoProveedores = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoProveedores = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _costoController.dispose();
    super.dispose();
  }

Future<void> _cargarProductos() async {
    setState(() => _isLoading = true);
    try {
      final prods = await ApiService.getProductos();
      setState(() {
        _productos = prods;
        _isLoading = false;
      });
      // Precarga de quiebre de stock: preseleccionar el producto inicial.
      final idInicial = widget.productoInicialId;
      if (idInicial != null && mounted) {
        for (final p in _productos) {
          if (p.productoId == idInicial) {
            setState(() {
              _productoSeleccionado = p;
              _costoController.text = p.costoPromedio.toString();
            });
            break;
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e')),
        );
      }
    }
  }

  Future<void> _registrarEntrada() async {
    if (_productoSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione un producto')));
      return;
    }

    if (_proveedorSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione un proveedor')));
      return;
    }

    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final costo = double.tryParse(_costoController.text.trim()) ?? 0.0;

    if (cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese una cantidad válida')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Payload esperado por POST /api/notas (createNotaEntrega).
    final proveedorMap = _proveedorSeleccionado as Map;
    final data = {
      'Numero_Nota': _generarNumeroNota(),
      'Proveedor_ID': proveedorMap['Proveedor_ID'],
      'Forma_Pago': _formaPago,
      'detalles': [
        {
          'Producto_ID': _productoSeleccionado!.productoId,
          'Cantidad': cantidad,
          'Costo_Unitario': costo,
        },
      ],
    };

    try {
      final success = await ApiService.registrarEntradaMercancia(data);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Entrada de mercancía registrada exitosamente'),
            ),
          );
          _cantidadController.clear();
          _costoController.clear();
          setState(() => _productoSeleccionado = null);
          _cargarProductos();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al procesar la entrada de mercancía'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error de servidor: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text('Entradas de Mercancía'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
const Text(
                    'Recepcionar Stock',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  if (_idsBajoStock.isNotEmpty) ...[
                    Text(
                      'Pre-carga por quiebre de stock:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _productos
                          .where((p) => _idsBajoStock.contains(p.productoId))
                          .map(
                            (p) => ActionChip(
                              avatar: const Icon(Icons.inventory, size: 16),
                              label: Text(
                                '${p.skuCodigo} · ${p.nombre} (${p.stockActual})',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                setState(() {
                                  _productoSeleccionado = p;
                                  _costoController.text =
                                      p.costoPromedio.toString();
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<ProductoModel>(
                    initialValue: _productoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Producto',
                      border: OutlineInputBorder(),
                    ),
                    items: _productos.map((prod) {
                      return DropdownMenuItem<ProductoModel>(
                        value: prod,
                        child: Text(
                          '${prod.skuCodigo} - ${prod.nombre} (Stock: ${prod.stockActual})',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _productoSeleccionado = val;
                        if (val != null) {
                          _costoController.text = val.costoPromedio.toString();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<dynamic>(
                    initialValue: _proveedorSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor',
                      border: OutlineInputBorder(),
                    ),
                    items: _proveedores.map((prov) {
                      final map = prov as Map;
                      final rif = map['RIF_Cedula'] ?? 'S/R';
                      final razon = map['Razon_Social'] ?? 'Proveedor';
                      return DropdownMenuItem<dynamic>(
                        value: prov,
                        child: Text('$rif - $razon'),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _proveedorSeleccionado = val),
                    hint: _cargandoProveedores
                        ? const Text('Cargando proveedores...')
                        : const Text('Seleccione un proveedor'),
                  ),
                  const SizedBox(height: 16),
                  // Selector de Forma de Pago (Contado / Crédito)
                  Row(
                    children: [
                      Icon(Icons.payment, size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      const Text(
                        'Forma de Pago:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(
                              value: 'Contado',
                              label: Text('Contado'),
                              icon: Icon(Icons.money, size: 18),
                            ),
                            ButtonSegment<String>(
                              value: 'Credito',
                              label: Text('Crédito'),
                              icon: Icon(Icons.credit_card, size: 18),
                            ),
                          ],
                          selected: {_formaPago},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _formaPago = newSelection.first;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _cantidadController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad Ingresada',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _costoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Costo Unitario Compra (\$)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart),
                      label: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Text(_formaPago == 'Contado'
                              ? 'Registrar Entrada (Contado)'
                              : 'Registrar Entrada (Crédito)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _formaPago == 'Contado'
                            ? cs.primary
                            : cs.secondary,
                        foregroundColor: _formaPago == 'Contado'
                            ? cs.onPrimary
                            : cs.onSecondary,
                      ),
                      onPressed: _isLoading ? null : _registrarEntrada,
                    ),
                  ),
                  if (_formaPago == 'Credito') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.onSecondaryContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'En crédito: se registrará una cuenta por pagar al proveedor. No afecta caja.',
                              style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
