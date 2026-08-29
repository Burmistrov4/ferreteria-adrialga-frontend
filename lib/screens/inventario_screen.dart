import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../services/api_service.dart';
import '../widgets/producto_dialog.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar inventario: $e')),
        );
      }
    }
  }

  List<ProductoModel> get _productosFiltrados {
    if (_searchQuery.isEmpty) return _productos;
    return _productos.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.nombre.toLowerCase().contains(q) ||
          p.skuCodigo.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _abrirDialogoProducto([ProductoModel? producto]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          ProductoDialog(producto: producto, categorias: _categorias),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              producto == null
                  ? 'Error al crear el producto'
                  : 'Error al actualizar el producto',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _eliminarProducto(ProductoModel producto) async {
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
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
          const SnackBar(
            content: Text('Error al eliminar el producto'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Inventario'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirDialogoProducto(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Producto'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por SKU o Nombre',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _productosFiltrados.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final prod = _productosFiltrados[index];
                        final bajoStock = prod.stockActual <= prod.stockMinimo;
                        return ListTile(
                          title: Text(
                            prod.nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'SKU: ${prod.skuCodigo} | Stock: ${prod.stockActual} (Mín: ${prod.stockMinimo})',
                          ),
                          leading: CircleAvatar(
                            backgroundColor: bajoStock
                                ? Colors.red.shade100
                                : Colors.blue.shade100,
                            child: Icon(
                              bajoStock ? Icons.warning : Icons.inventory_2,
                              color: bajoStock ? Colors.red : Colors.blue,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${prod.precioVenta.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _abrirDialogoProducto(prod),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _eliminarProducto(prod),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
