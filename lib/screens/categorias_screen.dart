import 'package:flutter/material.dart';

import '../models/categoria_model.dart';
import '../services/api_service.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  List<CategoriaModel> _categorias = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    setState(() => _isLoading = true);
    try {
      final cats = await ApiService.getCategorias();
      setState(() {
        _categorias = cats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _crearCategoria() async {
    final result = await _dialogoCategoria();
    if (result != null) {
      final ok = await ApiService.createCategoria(
        result['Nombre'].toString(),
        result['Descripcion']?.toString() ?? '',
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear la categoría')),
        );
      } else {
        _cargarCategorias();
      }
    }
  }

  Future<void> _editarCategoria(CategoriaModel categoria) async {
    final result = await _dialogoCategoria(categoria);
    if (result != null) {
      final res = await ApiService.updateCategoria(
        categoria.categoriaId,
        result,
      );
      if (mounted) {
        if (res['success'] == true) {
          _cargarCategorias();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar: ${res['error']}')),
          );
        }
      }
    }
  }

  Future<void> _eliminarCategoria(CategoriaModel categoria) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar Categoría'),
        content: Text(
          '¿Desactivar la categoría "${categoria.nombreCategoria}"? '
          'Los productos asociados conservarán su referencia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await ApiService.deleteCategoria(categoria.categoriaId);
      if (mounted) {
        if (res['success'] == true) {
          _cargarCategorias();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: ${res['error']}')),
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _dialogoCategoria(
    [CategoriaModel? categoria,
  ]) async {
    final nombreCtrl = TextEditingController(text: categoria?.nombreCategoria ?? '');
    final descCtrl = TextEditingController(text: categoria?.descripcion ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(categoria == null ? 'Nueva Categoría' : 'Editar Categoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true && nombreCtrl.text.trim().isNotEmpty) {
      return {
        'Nombre': nombreCtrl.text.trim(),
        'Descripcion': descCtrl.text.trim(),
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Categorías')),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearCategoria,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _categorias.length,
              itemBuilder: (context, index) {
                final cat = _categorias[index];
                return ListTile(
                  leading: CircleAvatar(child: Icon(cat.activo ? Icons.category : Icons.block)),
                  title: Text(cat.nombreCategoria),
                  subtitle: Text(cat.descripcion ?? 'Sin descripción'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editarCategoria(cat),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminarCategoria(cat),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
