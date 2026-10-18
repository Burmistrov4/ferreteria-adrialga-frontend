import 'dart:async';

import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/responsive.dart';
import '../widgets/producto_dialog.dart';
import '../widgets/matrix_stock_grid.dart';
import '../widgets/walkthrough_overlay.dart';
import 'categorias_screen.dart';

/// FASE C · Inventario gerencial.
///
/// El catálogo EPA elevó el inventario a ~7.200 ítems y 698 subcategorías.
/// Esta pantalla se rediseñó para ese volumen:
///  - **Paginación y filtro en servidor** (`/productos?limit&offset&q&categoriaId`):
///    nunca se descarga el catálogo completo al cliente (colapsaba la tabla).
///  - **Tabla densa** (`dataRowMinHeight/MaxHeight`) con columna de miniatura
///    WebP servida por el backend (`/productos/{sku}.webp`).
///  - **Filtro en árbol**: Categoría Padre -> Subcategoría -> Productos,
///    resolvedor de subárbol para incluir descendientes de cualquier nivel.
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

  // Paginación en servidor.
  int _total = 0;
  int _pagina = 0; // 0-based
  int _porPagina = 50;
  static const List<int> _opcionesPorPagina = [25, 50, 100];

  // Filtro en árbol: null = sin filtro (todas).
  int? _categoriaPadreId;
  int? _categoriaFiltroId;

  /// Filtro por proveedor de compra: null = todos; 0 = sin proveedor atribuible;
  /// >0 = Proveedor_ID (vínculo derivado de las notas de entrega / procedencia EPA).
  int? _proveedorId;
  List<Map<String, dynamic>> _proveedores = [];

  /// Filtro de existencias aplicado en servidor y conservando paginación.
  /// 'todos' | 'con' (stock > 0) | 'sin' (stock <= 0).
  String _filtroStock = 'todos';

  Timer? _debounceBusqueda;

  @override
  void initState() {
    super.initState();
    // Solo cambios de inventario/ventas afectan este listado. Escuchar el
    // evento global provocaba recargas por caja, proveedores y otros módulos.
    SocketService.onDbUpdateModulo(_alRecibirDbUpdate);
    _cargarDatos();
    // FASE C: tutorial CONTEXTUAL del módulo (solo la 1ª visita). Se agenda
    // post-frame porque el Overlay raíz aún no existe durante initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WalkthroughPrefs.mostrarSiAplica(
        context,
        modulo: 'inventario',
        pasos: walkthroughInventario(),
      );
    });
  }

  @override
  void dispose() {
    _debounceBusqueda?.cancel();
    SocketService.offDbUpdateModulo(_alRecibirDbUpdate);
    super.dispose();
  }

  /// Reacción al evento `db_update` del WebSocket LAN: recarga vía setState
  /// sin activar el spinner de pantalla completa, evitando parpadeos
  /// mientras el almacenista navega por el listado.
  void _alRecibirDbUpdate(String modulo) {
    if (!mounted) return;
    if (modulo == 'categorias') {
      _cargarDatos(silencioso: true, recargarCategorias: true);
      return;
    }
    if (modulo != 'ventas' &&
        modulo != 'inventario' &&
        modulo != '__reconexion__')
      return;
    _cargarDatos(silencioso: true);
  }

  Future<void> _cargarDatos({
    bool silencioso = false,
    bool recargarCategorias = false,
  }) async {
    if (!mounted) return;
    if (!silencioso) setState(() => _isLoading = true);
    try {
      // Las 698 categorías son un catálogo relativamente estático para esta
      // pantalla. No se vuelven a descargar en cada búsqueda/paginación;
      // solo se refrescan al entrar, tras gestionar categorías o si aún no
      // están cargadas. La consulta de productos sí permanece remota.
      final cats = (recargarCategorias || _categorias.isEmpty)
          ? await ApiService.getCategorias()
          : _categorias;
      final provs = _proveedores.isEmpty
          ? await ApiService.getProveedores()
          : _proveedores;
      final pagina = await ApiService.getProductosPaginados(
        limit: _porPagina,
        offset: _pagina * _porPagina,
        q: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        categoriaIds: _idsSubarbol(),
        conStock: _filtroStock == 'con',
        sinStock: _filtroStock == 'sin',
        proveedorId: _proveedorId,
      );
      if (!mounted) return;
      setState(() {
        _categorias = cats;
        _proveedores = (provs as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _productos = pagina.datos;
        _total = pagina.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar inventario: $e'),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  // ── Árbol de categorías ───────────────────────────────────────────────────

  /// Categorías raíz (sin padre).
  List<CategoriaModel> get _categoriasRaiz =>
      _categorias.where((c) => c.categoriaPadreId == null).toList()
        ..sort((a, b) => a.nombreCategoria.compareTo(b.nombreCategoria));

  /// Hijas directas de la categoría padre seleccionada.
  List<CategoriaModel> get _subcategorias {
    if (_categoriaPadreId == null) return const [];
    return _categorias
        .where((c) => c.categoriaPadreId == _categoriaPadreId)
        .toList()
      ..sort((a, b) => a.nombreCategoria.compareTo(b.nombreCategoria));
  }

  /// Ids del subárbol a filtrar: la categoría elegida (padre o subcategoría)
  /// MÁS todos sus descendientes, para que "Categoría Padre" incluya realmente
  /// sus productos aunque estén en hojas de 2º/3º nivel.
  List<int>? _idsSubarbol() {
    final raiz = _categoriaFiltroId ?? _categoriaPadreId;
    if (raiz == null) return null;
    final ids = <int>[raiz];
    void recorrer(int id) {
      for (final c in _categorias) {
        if (c.categoriaPadreId == id && !ids.contains(c.categoriaId)) {
          ids.add(c.categoriaId);
          recorrer(c.categoriaId);
        }
      }
    }

    recorrer(raiz);
    return ids;
  }

  void _seleccionarPadre(int? id) {
    setState(() {
      _categoriaPadreId = id;
      _categoriaFiltroId =
          null; // al cambiar el padre se limpia la subcategoría
      _pagina = 0;
    });
    _cargarDatos();
  }

  void _seleccionarSubcategoria(int? id) {
    setState(() {
      _categoriaFiltroId = id;
      _pagina = 0;
    });
    _cargarDatos();
  }

  void _alBuscar(String valor) {
    setState(() => _searchQuery = valor);
    _debounceBusqueda?.cancel();
    _debounceBusqueda = Timer(const Duration(milliseconds: 350), () {
      setState(() => _pagina = 0);
      _cargarDatos(silencioso: true);
    });
  }

  int get _totalPaginas =>
      _total == 0 ? 1 : ((_total + _porPagina - 1) ~/ _porPagina);

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _abrirDialogoProducto([ProductoModel? producto]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoDialog(
        producto: producto,
        categorias: _categorias,
        onCategoriaCreada: (cat) {
          setState(() => _categorias.add(cat));
          _cargarDatos(recargarCategorias: true);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(
              content: Text('Producto desactivado (ya no se vende)'),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ApiService.ultimoErrorProducto ??
                  'Error al eliminar el producto',
            ),
            backgroundColor: cs.error,
          ),
        );
      }
    }
  }

  /// Abre la pantalla de gestión de categorías (crear/editar/desactivar).
  /// Al volver, refresca explícitamente el catálogo de categorías; las demás
  /// recargas de inventario reutilizan el catálogo ya cargado.
  Future<void> _abrirGestionCategorias() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriasScreen()),
    );
    _cargarDatos(recargarCategorias: true);
  }

  // ── Miniatura WebP ────────────────────────────────────────────────────────

  /// Miniatura del producto servida por el backend.
  ///
  /// [ApiService.urlImagen] resuelve la ruta relativa del catálogo EPA
  /// (`/productos/SKU.webp`) a URL absoluta. `cacheWidth` limita el decodificado
  /// en memoria (crítico con 7.000 imágenes); sin `cached_network_image` en el
  /// pubspec se usa la caché de red nativa de Flutter.
  Widget _miniatura(ProductoModel prod, {double size = 40}) {
    final url = ApiService.urlImagen(prod.imagenUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url == null
          ? Icon(Icons.inventory_2_outlined, size: size * 0.6)
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) =>
                  Icon(Icons.image_not_supported_outlined, size: size * 0.6),
            ),
    );
  }

  // ── Filtro en árbol ───────────────────────────────────────────────────────

  /// Selector jerárquico: Categoría Padre -> Subcategoría (ambos con "Todas").
  /// Se envuelve en `LayoutBuilder`/`Wrap` para no desbordar en pantallas
  /// estrechas (regla de oro de responsividad del proyecto).
  Widget _buildFiltroArbol() {
    if (_categorias.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    Widget selector({
      required String etiqueta,
      required int? valor,
      required List<CategoriaModel> opciones,
      required ValueChanged<int?> onCambio,
      required String textoNulo,
    }) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
        child: DropdownButtonFormField<int?>(
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: etiqueta,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: <DropdownMenuItem<int?>>[
            DropdownMenuItem<int?>(
              value: null,
              child: Text(textoNulo, overflow: TextOverflow.ellipsis),
            ),
            ...opciones.map(
              (c) => DropdownMenuItem<int?>(
                value: c.categoriaId,
                child: Text(c.nombreCategoria, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: onCambio,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            selector(
              etiqueta: 'Categoría Padre',
              valor: _categoriaPadreId,
              opciones: _categoriasRaiz,
              textoNulo: 'Todas las categorías',
              onCambio: _seleccionarPadre,
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int?>(
                initialValue: _proveedorId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Proveedor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos los proveedores',
                        overflow: TextOverflow.ellipsis),
                  ),
                  // El ID puede llegar como String desde la API: se parsea sin
                  // castear y se descartan los registros no numéricos (un null
                  // aquí duplicaría la opción "Todos los proveedores").
                  ..._proveedores
                      .where((p) =>
                          double.tryParse(
                            p['Proveedor_ID']?.toString() ?? '',
                          ) !=
                          null)
                      .map(
                        (p) => DropdownMenuItem<int?>(
                          value: double.tryParse(
                            p['Proveedor_ID'].toString(),
                          )?.toInt(),
                          child: Text(
                            '${p['Razon_Social'] ?? '—'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  const DropdownMenuItem<int?>(
                    value: 0,
                    child: Text('Sin proveedor atribuible',
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (valor) {
                  if (!mounted) return;
                  setState(() {
                    _proveedorId = valor;
                    _pagina = 0;
                  });
                  _cargarDatos(silencioso: true);
                },
              ),
            ),
            if (_categoriaPadreId != null)
              selector(
                etiqueta: 'Subcategoría',
                valor: _categoriaFiltroId,
                opciones: _subcategorias,
                textoNulo: 'Todas las subcategorías',
                onCambio: _seleccionarSubcategoria,
              ),
            // Ruta (breadcrumb) del filtro activo, para orientar al usuario.
            if (_categoriaPadreId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _rutaFiltro(),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: _filtroStock,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Existencias',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'con', child: Text('Con existencia')),
                  DropdownMenuItem(value: 'sin', child: Text('Sin existencia')),
                ],
                onChanged: (valor) {
                  if (valor == null || !mounted) return;
                  setState(() {
                    _filtroStock = valor;
                    _pagina = 0;
                  });
                  _cargarDatos(silencioso: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rutaFiltro() {
    final nombrePadre = _categorias
        .firstWhere(
          (c) => c.categoriaId == _categoriaPadreId,
          orElse: () => CategoriaModel(categoriaId: -1, nombreCategoria: '—'),
        )
        .nombreCategoria;
    if (_categoriaFiltroId == null) return nombrePadre;
    final nombreSub = _categorias
        .firstWhere(
          (c) => c.categoriaId == _categoriaFiltroId,
          orElse: () => CategoriaModel(categoriaId: -1, nombreCategoria: '—'),
        )
        .nombreCategoria;
    return '$nombrePadre  ›  $nombreSub';
  }

  // ── Paginación ────────────────────────────────────────────────────────────

  Widget _buildPaginacion(ColorScheme cs) {
    final desde = _total == 0 ? 0 : _pagina * _porPagina + 1;
    final hasta = (_pagina * _porPagina + _productos.length).clamp(0, _total);
    final ancho = MediaQuery.sizeOf(context).width;
    final compacto = ancho < 600;

    final resumen = Text(
      '$desde–$hasta de $_total productos',
      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
    );
    final porPagina = SizedBox(
      width: compacto ? 105 : 110,
      height: 48,
      child: DropdownButtonFormField<int>(
        initialValue: _porPagina,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Por página',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _opcionesPorPagina
            .map((n) => DropdownMenuItem<int>(value: n, child: Text('$n')))
            .toList(),
        onChanged: (n) {
          if (n == null) return;
          setState(() {
            _porPagina = n;
            _pagina = 0;
          });
          _cargarDatos();
        },
      ),
    );

    final anterior = IconButton.filledTonal(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.chevron_left),
      tooltip: 'Anterior',
      onPressed: _pagina > 0
          ? () {
              setState(() => _pagina--);
              _cargarDatos();
            }
          : null,
    );
    final siguiente = IconButton.filledTonal(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.chevron_right),
      tooltip: 'Siguiente',
      onPressed: (_pagina + 1) < _totalPaginas
          ? () {
              setState(() => _pagina++);
              _cargarDatos();
            }
          : null,
    );
    final pagina = Text('Página ${_pagina + 1} de $_totalPaginas');

    if (compacto) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [resumen, porPagina],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              anterior,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: pagina,
              ),
              siguiente,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        resumen,
        const SizedBox(width: 8),
        porPagina,
        const Spacer(),
        anterior,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: pagina,
        ),
        // Hueco para el FAB "Nuevo Producto": antes el botón de página
        // siguiente quedaba debajo del FAB y no se podía pulsar.
        const SizedBox(width: 170),
        siguiente,
      ],
    );
  }

  Widget _buildVistaProductos(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar por SKU, nombre, marca o código EPA',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: _alBuscar,
        ),
        const SizedBox(height: 12),
        _buildFiltroArbol(),
        const SizedBox(height: 12),
        Expanded(
          child: _productos.isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 40,
                        color: cs.outline,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No hay productos que coincidan con el filtro',
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Vista adaptativa: tabla densa en escritorio, tarjetas
                    // (con bottom sheet de detalle) en pantallas móviles.
                    if (constraints.maxWidth >= 600) {
                      return _vistaTablaEscritorio(cs);
                    }
                    return _vistaTarjetasMovil(cs);
                  },
                ),
        ),
        const SizedBox(height: 8),
        _buildPaginacion(cs),
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
                Row(
                  children: [
                    _miniatura(prod, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        prod.nombre,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _filaDetalle('SKU', prod.skuCodigo),
                _filaDetalle(
                  'Precio de venta',
                  '\$${prod.precioVenta.toStringAsFixed(2)}',
                ),
                _filaDetalle(
                  'Costo de compra',
                  '\$${prod.costoUltimo.toStringAsFixed(2)}',
                ),
                _filaDetalle(
                  'Margen',
                  '${prod.margenGanancia.toStringAsFixed(1)}%',
                ),
                _filaDetalle(
                  'Stock global',
                  '${prod.stockActual} uds (mínimo ${prod.stockMinimo})',
                  color: bajoStock ? cs.error : null,
                ),
                const SizedBox(height: 14),
                // Matriz de variantes en acordeón: micro-edición tactil.
                Text(
                  'Variantes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
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
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Móvil (<600): tarjetas densas con miniatura WebP, nombre truncado a 2
  /// líneas, precio y chip de stock. Tap → bottom sheet con lo secundario.
  Widget _vistaTarjetasMovil(ColorScheme cs) {
    return ListView.separated(
      itemCount: _productos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final prod = _productos[index];
        final bajoStock = prod.stockActual <= prod.stockMinimo;
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _mostrarDetalleProducto(context, prod),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _miniatura(prod, size: 44),
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
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
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
                                horizontal: 8,
                                vertical: 2,
                              ),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

  /// Escritorio (≥600): **tabla densa** con miniatura WebP y scroll horizontal.
  ///
  /// `dataRowMinHeight/MaxHeight` acotados (44/56) y `headingRowHeight` 44
  /// permiten ver ~2x más filas que antes; el paginado en servidor garantiza
  /// que nunca se construyan las 7.000 filas en un solo frame.
  Widget _vistaTablaEscritorio(ColorScheme cs) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        // Espacio inferior para que el FAB "Nuevo Producto" no tape la última
        // fila ni los botones de acciones (antes se solapaban).
        padding: const EdgeInsets.only(bottom: 96),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            // Más separación entre columnas y sin margen lateral: la tabla
            // aprovecha el ancho disponible en vez de dejar una franja vacía.
            columnSpacing: 26,
            horizontalMargin: 0,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            headingRowHeight: 44,
            columns: const [
              DataColumn(label: SizedBox(width: 44, child: Text('Img'))),
              DataColumn(label: Text('Ítem')),
              DataColumn(label: Text('SKU')),
              DataColumn(label: Text('Categoría')),
              DataColumn(label: Text('Precio'), numeric: true),
              DataColumn(label: Text('Margen'), numeric: true),
              DataColumn(label: Text('Stock'), numeric: true),
              DataColumn(label: Text('Acciones')),
            ],
            rows: _productos.map((prod) {
              final bajoStock = prod.stockActual <= prod.stockMinimo;
              String? cat;
              for (final c in _categorias) {
                if (c.categoriaId == prod.categoriaId) {
                  cat = c.nombreCategoria;
                  break;
                }
              }
              return DataRow(
                cells: [
                  DataCell(_miniatura(prod)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        prod.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(prod.skuCodigo, style: const TextStyle(fontSize: 12)),
                  ),
                  DataCell(
                    Text(
                      cat ?? '—',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(Text('\$${prod.precioVenta.toStringAsFixed(2)}')),
                  DataCell(Text('${prod.margenGanancia.toStringAsFixed(1)}%')),
                  DataCell(
                    Text(
                      bajoStock
                          ? '${prod.stockActual} ⚠'
                          : '${prod.stockActual}',
                      style: TextStyle(
                        color: bajoStock ? cs.error : null,
                        fontWeight: bajoStock
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            Icons.grid_on_outlined,
                            color: cs.tertiary,
                          ),
                          tooltip: 'Matriz de variantes',
                          onPressed: () => _mostrarMatrizProducto(prod, cs),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(Icons.edit_outlined, color: cs.primary),
                          tooltip: 'Editar producto',
                          onPressed: () => _abrirDialogoProducto(prod),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
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
          title: Text(
            AdrialgaResponsive.isMobile(MediaQuery.sizeOf(context).width)
                ? 'Inventario'
                : 'Gestión de Inventario',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!AdrialgaResponsive.isMobile(MediaQuery.sizeOf(context).width))
              IconButton(
                icon: const Icon(Icons.category),
                onPressed: _abrirGestionCategorias,
                tooltip: 'Gestionar categorías',
              ),
            if (AdrialgaResponsive.isMobile(MediaQuery.sizeOf(context).width))
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                onSelected: (value) {
                  if (value == 'categorias') _abrirGestionCategorias();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'categorias',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.category),
                      title: Text('Gestionar categorías'),
                    ),
                  ),
                ],
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
