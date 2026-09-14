import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../services/api_service.dart';
import '../widgets/producto_dialog.dart';
import '../widgets/matrix_stock_grid.dart';
import 'categorias_screen.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  List<ProductoModel> _productos = [];
  List<CategoriaModel> _categorias = [];
  String _searchQuery = '';
  bool _isLoading = true;
  int? _categoriaFiltroId; // null = Todas las categorías

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      final prods = await ApiService.getProductos();
      final cats = await ApiService.getCategorias();
      setState(() {
        _productos = prods;
        _categorias = cats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar inventario: $e'),
            backgroundColor: cs.error,
          ),
        );
      }
    }
  }

  List<ProductoModel> get _productosFiltrados {
    return _productos.where((p) {
      // Filtro por categoría seleccionada (null = todas)
      if (_categoriaFiltroId != null &&
          p.categoriaId != _categoriaFiltroId) {
        return false;
      }
      // Filtro por texto (nombre o SKU)
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.nombre.toLowerCase().contains(q) ||
          p.skuCodigo.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _abrirDialogoProducto([ProductoModel? producto]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoDialog(
        producto: producto,
        categorias: _categorias,
        onCategoriaCreada: (cat) {
          setState(() => _categorias.add(cat));
          _cargarDatos();
        },
      ),
    );

    if (result != null) {
      bool exito = false;
      if (producto == null) {
        exito = await ApiService.createProducto(result);
      } else {
        exito = await ApiService.updateProducto(producto.productoId, result);
      }

      if (exito) {
        _cargarDatos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                producto == null ? 'Producto creado' : 'Producto actualizado',
              ),
            ),
          );
        }
      } else if (mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              producto == null
                  ? 'Error al crear el producto'
                  : 'Error al actualizar el producto',
            ),
            backgroundColor: cs.error,
          ),
        );
      }
    }
  }

  Future<void> _eliminarProducto(ProductoModel producto) async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Está seguro de eliminar "${producto.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await ApiService.deleteProducto(producto.productoId);
      if (ok) {
        _cargarDatos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Producto eliminado')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al eliminar el producto'),
            backgroundColor: cs.error,
          ),
        );
      }
    }
  }

  /// Abre la pantalla de gestión de categorías (crear/editar/desactivar).
  /// Al volver, recarga los datos para refrescar el filtro por categoría.
  Future<void> _abrirGestionCategorias() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriasScreen()),
    );
    _cargarDatos();
  }

  /// Barra de filtros por categoría: chip "Todas" + uno por categoría.
  Widget _buildFiltroCategorias() {
    if (_categorias.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categorias.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ChoiceChip(
              label: const Text('Todas'),
              selected: _categoriaFiltroId == null,
              onSelected: (_) => setState(() => _categoriaFiltroId = null),
            );
          }
          final cat = _categorias[index - 1];
          return ChoiceChip(
            label: Text(cat.nombreCategoria),
            selected: _categoriaFiltroId == cat.categoriaId,
            onSelected: (sel) => setState(
              () => _categoriaFiltroId = sel ? cat.categoriaId : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildVistaProductos(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar por SKU o Nombre',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
        const SizedBox(height: 12),
        _buildFiltroCategorias(),
        const SizedBox(height: 12),
        Expanded(
          child: _productosFiltrados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 40, color: cs.outline),
                      const SizedBox(height: 8),
                      const Text(
                        'No hay productos que coincidan con el filtro',
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Vista adaptativa: tabla de grilla en escritorio, tarjetas
                    // (con bottom sheet de detalle) en pantallas móviles.
                    if (constraints.maxWidth >= 600) {
                      return _vistaTablaEscritorio(cs);
                    }
                    return _vistaTarjetasMovil(cs);
                  },
                ),
        ),
      ],
    );
  }

  /// Detalle completo y acciones en hoja inferior (módulo móvil): todos los
  /// botones ≥48dp, contenido desplazable para nunca desbordar.
  void _mostrarDetalleProducto(BuildContext context, ProductoModel prod) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bajoStock = prod.stockActual <= prod.stockMinimo;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prod.nombre,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _filaDetalle('SKU', prod.skuCodigo),
                _filaDetalle('Precio de venta',
                    '\$${prod.precioVenta.toStringAsFixed(2)}'),
                _filaDetalle('Costo de compra',
                    '\$${prod.costoUltimo.toStringAsFixed(2)}'),
                _filaDetalle('Margen', '${prod.margenGanancia.toStringAsFixed(1)}%'),
                _filaDetalle(
                  'Stock global',
                  '${prod.stockActual} uds (mínimo ${prod.stockMinimo})',
                  color: bajoStock ? cs.error : null,
                ),
                const SizedBox(height: 14),
                // Matriz de variantes en acordeón: micro-edición tactil.
                Text('Variantes',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: cs.onSurface)),
                const SizedBox(height: 6),
                MatrixStockGrid(
                  productoId: prod.productoId,
                  skuBase: prod.skuCodigo,
                  nombreProducto: prod.nombre,
                  compacto: true,
                  onCambio: _cargarDatos,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        icon: Icon(Icons.edit_outlined, color: cs.primary),
                        label: const Text('Editar'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _abrirDialogoProducto(prod);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _eliminarProducto(prod);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filaDetalle(String etiqueta, String valor, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Móvil (<600): tarjetas con datos críticos (avatar, nombre truncado a 2
  /// líneas, precio y chip de stock). Tap → bottom sheet con lo secundario.
  Widget _vistaTarjetasMovil(ColorScheme cs) {
    return ListView.separated(
      itemCount: _productosFiltrados.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final prod = _productosFiltrados[index];
        final bajoStock = prod.stockActual <= prod.stockMinimo;
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _mostrarDetalleProducto(context, prod),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: bajoStock
                        ? cs.errorContainer
                        : cs.primaryContainer,
                    child: Icon(
                      bajoStock ? Icons.warning_amber : Icons.inventory_2,
                      color: bajoStock
                          ? cs.onErrorContainer
                          : cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prod.nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '\$${prod.precioVenta.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: bajoStock
                                    ? cs.error
                                    : cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Stock: ${prod.stockActual}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: bajoStock
                                      ? cs.onError
                                      : cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Matriz matricial en diálogo para escritorio: grilla cruzada completa
  /// con scroll bidireccional y edición inline por celda.
  void _mostrarMatrizProducto(ProductoModel prod, ColorScheme cs) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.grid_on, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Matriz de variantes · ${prod.nombre}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: MatrixStockGrid(
                    productoId: prod.productoId,
                    skuBase: prod.skuCodigo,
                    nombreProducto: prod.nombre,
                    onCambio: _cargarDatos,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Escritorio (≥600): DataTable con scroll horizontal (columnas fijas).
  Widget _vistaTablaEscritorio(ColorScheme cs) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Ítem')),
              DataColumn(label: Text('SKU')),
              DataColumn(label: Text('Precio'), numeric: true),
              DataColumn(label: Text('Margen'), numeric: true),
              DataColumn(label: Text('Stock'), numeric: true),
              DataColumn(label: Text('Acciones')),
            ],
            rows: _productosFiltrados.map((prod) {
              final bajoStock = prod.stockActual <= prod.stockMinimo;
              return DataRow(
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        prod.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(prod.skuCodigo)),
                  DataCell(Text('\$${prod.precioVenta.toStringAsFixed(2)}')),
                  DataCell(Text('${prod.margenGanancia.toStringAsFixed(1)}%')),
                  DataCell(
                    Text(
                      bajoStock
                          ? '${prod.stockActual} ⚠'
                          : '${prod.stockActual}',
                      style: TextStyle(
                        color: bajoStock ? cs.error : null,
                        fontWeight:
                            bajoStock ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: Icon(Icons.grid_on_outlined, color: cs.tertiary),
                          tooltip: 'Matriz de variantes',
                          onPressed: () => _mostrarMatrizProducto(prod, cs),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: Icon(Icons.edit_outlined, color: cs.primary),
                          tooltip: 'Editar producto',
                          onPressed: () => _abrirDialogoProducto(prod),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: Icon(Icons.delete_outline, color: cs.error),
                          tooltip: 'Eliminar producto',
                          onPressed: () => _eliminarProducto(prod),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
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
          leading: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Regresar',
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('Gestión de Inventario'),
          actions: [
            IconButton(
              icon: const Icon(Icons.category),
              onPressed: _abrirGestionCategorias,
              tooltip: 'Gestionar categorías',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cargarDatos,
              tooltip: 'Actualizar',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          onPressed: _abrirDialogoProducto,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo Producto'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildVistaProductos(context),
              ),
      ),
    );
  }
}
