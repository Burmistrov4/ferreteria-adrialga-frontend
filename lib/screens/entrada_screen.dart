import 'package:flutter/material.dart';

import '../models/categoria_model.dart';
import '../models/producto_model.dart';
import '../models/variante_model.dart';
import '../services/api_service.dart';
import '../services/shortcut_service.dart';
import '../widgets/producto_dialog.dart';

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

  // ── Matriz/variantes + CPP predictivo (Fase 6, M4) ─────────────────────
  List<ProductoVariante> _variantes = [];
  ProductoVariante? _varianteSeleccionada;
  bool _cargandoVariantes = false;
  final _margenCtrl = TextEditingController();

  /// Último texto tipeado en el buscador de producto (para ofrecer la
  /// creación contextual "Crear nuevo producto: X").
  String _ultimaBusqueda = '';

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
    _margenCtrl.dispose();
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
              _costoController.text = _costoSugerido(p);
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

  /// Sugiere el costo de compra: si el producto ya tiene costo promedio, lo
  /// usa (compra previa conocida); si no, propone un costo que preserve un
  /// margen de reventa de ~30% sobre el precio de venta (Precio / 1.30).
  String _costoSugerido(ProductoModel p) {
    if (p.costoPromedio > 0) return p.costoPromedio.toStringAsFixed(2);
    if (p.precioVenta > 0) return (p.precioVenta / 1.30).toStringAsFixed(2);
    return '0.00';
  }

  /// Carga las variantes del producto seleccionado para el selector de
  /// entrada (si solo existe la variante por defecto, se oculta el selector).
  Future<void> _cargarVariantesDe(ProductoModel p) async {
    setState(() {
      _cargandoVariantes = true;
      _variantes = [];
      _varianteSeleccionada = null;
    });
    try {
      final data = await ApiService.getVariantesProducto(p.productoId);
      final m = MatrizVariantes.fromJson(data);
      if (!mounted) return;
      setState(() {
        // Sin personalización: solo hereda la variante por defecto (creada
        // por el backfill) → se muestra como selector de "Default".
        _variantes = m.matriz.where((v) => m.matriz.length > 1 || m.ejes.isNotEmpty).toList();
        _varianteSeleccionada =
            _variantes.length == 1 ? _variantes.first : null;
        _cargandoVariantes = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoVariantes = false);
    }
  }

  /// Creación contextual desde el autocomplete: abre el diálogo de producto,
  /// persiste en el backend y selecciona el registro recién creado en la
  /// entrada (el flujo de compra no se interrumpe).
  Future<void> _crearProductoRapido(String nombreInicial) async {
    List<CategoriaModel> categorias = [];
    try {
      categorias = await ApiService.getCategorias();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar la lista de categorías')),
      );
      return;
    }
    if (!mounted) return;
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoDialog(categorias: categorias),
    );
    if (data == null) return;
    // Pre-llenar el nombre buscado por comodidad si el usuario abrió vacío.
    data['Nombre'] = (data['Nombre'] as String).trim();
    if (data['Nombre']!.isEmpty) data['Nombre'] = nombreInicial.trim();

    final creado = await ApiService.createProducto(data);
    if (!mounted) return;
    if (creado) {
      await _cargarProductos();
      if (!mounted) return;
      // Seleccionar el producto recién creado (mayor ID = el último).
      try {
        final nuevo = _productos.firstWhere(
            (p) => p.nombre == data['Nombre'] && p.skuCodigo == data['SKU_Codigo']);
        _alSeleccionarProducto(nuevo);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Producto "${nuevo.nombre}" creado y agregado a la entrada')),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto creado; selecciónalo en el buscador')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear el producto')),
      );
    }
  }

  /// Selección de producto desde autocomplete/chips: carga costo sugerido,
  /// margen editable y matriz de variantes.
  void _alSeleccionarProducto(ProductoModel p) {
    setState(() {
      _productoSeleccionado = p;
      _costoController.text = _costoSugerido(p);
      _margenCtrl.text =
          p.margenGanancia > 0 ? p.margenGanancia.toStringAsFixed(2) : '';
    });
    _cargarVariantesDe(p);
  }

  /// CPP estimado en vivo: (stockPrev·costoPrev + cant·costoCompra) /
  /// (stockPrev + cant). Con stockPrev==0 cae a costoCompra directamente.
  ({double cpp, double precio}) _vistaPreviaCpp() {
    final stockPrev = _varianteSeleccionada?.stock ??
        _productoSeleccionado?.stockActual ??
        0;
    final costoPrev = _varianteSeleccionada?.costo ??
        _productoSeleccionado?.costoPromedio ??
        0.0;
    final cantidad = double.tryParse(_cantidadController.text.trim()) ?? 0;
    final costoCompra =
        double.tryParse(_costoController.text.trim().replaceAll(',', '.')) ?? 0;
    if (cantidad <= 0 || costoCompra <= 0) {
      final margen = double.tryParse(
              _margenCtrl.text.trim().replaceAll(',', '.')) ??
          (_productoSeleccionado?.margenGanancia ?? 0);
      final precioRef = costoCompra > 0
          ? costoCompra * (1 + margen / 100)
          : (_productoSeleccionado?.precioVenta ?? 0);
      return (cpp: stockPrev > 0 ? costoPrev : costoCompra, precio: precioRef);
    }
    final denominador = stockPrev + cantidad;
    final cpp = stockPrev > 0
        ? ((stockPrev * costoPrev) + (cantidad * costoCompra)) / denominador
        : costoCompra; // Protección stock-cero: asignación directa.
    final margen = double.tryParse(
            _margenCtrl.text.trim().replaceAll(',', '.')) ??
        (_productoSeleccionado?.margenGanancia ?? 0);
    return (cpp: cpp, precio: cpp * (1 + margen / 100));
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
          if (_varianteSeleccionada != null)
            'Variante_ID': _varianteSeleccionada!.varianteId,
          'Cantidad': cantidad,
          'Costo_Unitario': costo,
        },
      ],
    };

    try {
      final res = await ApiService.registrarEntradaMercancia(data);

      if (mounted) {
        if (res['success'] == true) {
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
          // Error accionable: si no hay fondos en caja (SALDO_INSUFICIENTE),
          // el backend ya devuelve la guía (Crédito o Ingreso de Caja).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['error']?.toString() ??
                    'Error al procesar la entrada de mercancía',
              ),
              backgroundColor: res['tipo'] != null
                  ? Theme.of(context).colorScheme.error
                  : null,
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
                              onPressed: () => _alSeleccionarProducto(p),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Selector inteligente: búsqueda difusa + creación contextual
                  // (último ítem de la lista si no hay coincidencias).
                  Autocomplete<ProductoModel>(
                    displayStringForOption: (p) =>
                        '${p.skuCodigo} - ${p.nombre}',
                    fieldViewBuilder: (context, controller, focusNode,
                        onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                    },
                    optionsBuilder: (textEditingValue) {
                      _ultimaBusqueda = textEditingValue.text;
                      final q = textEditingValue.text.toLowerCase().trim();
                      if (q.isEmpty) return _productos;
                      return _productos.where((p) =>
                          p.nombre.toLowerCase().contains(q) ||
                          p.skuCodigo.toLowerCase().contains(q));
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      final lista = options.toList();
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 260, maxWidth: 480),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                ...lista.map((p) => ListTile(
                                      leading: const Icon(Icons.inventory_2,
                                          size: 20),
                                      title: Text(
                                          '${p.skuCodigo} - ${p.nombre}'),
                                      subtitle: Text(
                                          'Stock: ${p.stockActual} · \$${p.precioVenta.toStringAsFixed(2)}'),
                                      onTap: () => onSelected(p),
                                    )),
                                if (lista.isEmpty)
                                  ListTile(
                                    leading: Icon(Icons.add_circle,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    title: Text(
                                        '+ Crear nuevo producto'
                                        '${_ultimaBusqueda.isNotEmpty ? ': $_ultimaBusqueda' : ''}'),
                                    onTap: () {
                                      FocusScope.of(context).unfocus();
                                      _crearProductoRapido(_ultimaBusqueda);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    onSelected: _alSeleccionarProducto,
                  ),
                  const SizedBox(height: 16),
                  // ── Selector de variante (solo si el producto las tiene)
                  if (_cargandoVariantes)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: LinearProgressIndicator(),
                    )
                  else if (_variantes.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _variantes.map((v) {
                        final activa = v.varianteId == _varianteSeleccionada?.varianteId;
                        final etiqueta = v.atributos.isEmpty
                            ? v.sku
                            : v.atributos.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' · ');
                        return ChoiceChip(
                          selected: activa,
                          onSelected: (_) =>
                              setState(() => _varianteSeleccionada = activa ? null : v),
                          label: Text('$etiqueta (${v.stock})',
                              style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
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
                  Text(
                    'Forma de Pago',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment<String>(
                          value: 'Contado',
                          label: Text('Contado'),
                        ),
                        ButtonSegment<String>(
                          value: 'Credito',
                          label: Text('Crédito'),
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _cantidadController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad Ingresada',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _costoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Costo Unitario Compra (\$)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  // Margen editable + preview del CPP: muestra las fórmulas
                  // ejecutadas por el backend al confirmar la entrada.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _margenCtrl,
                          keyboardType: const TextInputType
                              .numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Margen % (aplicado al precio)',
                            hintText: _productoSeleccionado != null &&
                                    _productoSeleccionado!.margenGanancia > 0
                                ? 'Heredado: ${_productoSeleccionado!.margenGanancia.toStringAsFixed(2)}%'
                                : 'Ej. 25',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  // CPP estimado en vivo: calculado sobre el stock vigente
                  // (o de la variante seleccionada) — nunca divide por cero.
                  Builder(builder: (context) {
                    final p = _productoSeleccionado;
                    if (p == null) return const SizedBox.shrink();
                    final costo = double.tryParse(
                            _costoController.text.trim().replaceAll(',', '.')) ??
                        0;
                    if (costo <= 0) return const SizedBox.shrink();
                    final vista = _vistaPreviaCpp();
                    final cambio =
                        (vista.precio - p.precioVenta).abs() > 0.005;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'CPP estimado: \$${vista.cpp.toStringAsFixed(2)}'
                              '${_varianteSeleccionada != null ? ' (variante)' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'Precio de venta (margen ${(double.tryParse(_margenCtrl.text.trim().replaceAll(',', '.')) ?? p.margenGanancia).toStringAsFixed(2)}%): \$${vista.precio.toStringAsFixed(2)}'
                              '${cambio ? (vista.precio > p.precioVenta ? ' ↑' : ' ↓') : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
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
