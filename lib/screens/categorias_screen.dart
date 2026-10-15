import 'package:flutter/material.dart';

import '../models/categoria_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

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
    SocketService.onDbUpdateModulo(_alDbUpdate);
  }

  void _alDbUpdate(String modulo) {
    if (!mounted || (modulo != 'categorias' && modulo != '__reconexion__')) return;
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    setState(() => _isLoading = true);
    try {
      final cats = await ApiService.getCategorias();
      if (!mounted) return;
      setState(() {
        _categorias = cats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Antes se silenciaba el error: la pantalla quedaba vacía sin explicación.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron cargar las categorías: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _crearCategoria() async {
    // try/finally: una excepción en la API no debe dejar la UI colgada ni
    // impedir que el diálogo ya cerrado libere sus recursos.
    try {
      final result = await _dialogoCategoria();
      if (result == null || !mounted) return;
      final res = await ApiService.createCategoria(
        result['Nombre'].toString(),
        result['Descripcion']?.toString() ?? '',
      );
      if (!mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error']?.toString() ??
                'Error al crear la categoría'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        await _cargarCategorias();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo crear la categoría: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _editarCategoria(CategoriaModel categoria) async {
    try {
      final result = await _dialogoCategoria(categoria);
      if (result == null || !mounted) return;
      final res = await ApiService.updateCategoria(
        categoria.categoriaId,
        result,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        await _cargarCategorias();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: ${res['error']}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar la categoría: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _eliminarCategoria(CategoriaModel categoria) async {
    try {
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) return;
      final res = await ApiService.deleteCategoria(categoria.categoriaId);
      if (!mounted) return;
      if (res['success'] == true) {
        await _cargarCategorias();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: ${res['error']}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar la categoría: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Diálogo de alta/edición de categoría.
  ///
  /// BLINDAJE (Fase 1): los `TextEditingController` se crean aquí y DEBEN
  /// liberarse aquí. En la versión original `nombreCtrl`/`descCtrl` nunca se
  /// disponían → cada apertura dejaba dos controladores vivos con listeners
  /// sobre el `TextInput`, degradando el hilo de UI y contribuyendo al
  /// "freeze" de la pantalla opaca.
  ///
  /// El `content` NO usa `LayoutBuilder`: esa combinación es incompatible con
  /// el `IntrinsicWidth` interno de `AlertDialog` y lanza durante el build.
  /// Se usa `SingleChildScrollView` plano (el ancho lo fija el diálogo).
  Future<Map<String, dynamic>?> _dialogoCategoria(
    [CategoriaModel? categoria,
  ]) async {
    final nombreCtrl =
        TextEditingController(text: categoria?.nombreCategoria ?? '');
    final descCtrl = TextEditingController(text: categoria?.descripcion ?? '');

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title:
              Text(categoria == null ? 'Nueva Categoría' : 'Editar Categoría'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ],
            ),
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

      // El texto se extrae ANTES del finally (que dispone los controladores):
      // leer un controller ya liberado lanzaría.
      final nombre = nombreCtrl.text.trim();
      final descripcion = descCtrl.text.trim();
      if (result == true && nombre.isNotEmpty) {
        return {'Nombre': nombre, 'Descripcion': descripcion};
      }
      return null;
    } finally {
      // Liberación garantizada incluso si el diálogo lanza.
      nombreCtrl.dispose();
      descCtrl.dispose();
    }
  }

  @override
  void dispose() {
    SocketService.offDbUpdateModulo(_alDbUpdate);
    super.dispose();
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
          title: const Text('Gestión de Categorías'),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          onPressed: _crearCategoria,
          child: const Icon(Icons.add),
        ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categorias.isEmpty
              // Estado vacío explícito: antes la lista vacía no comunicaba nada.
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.category_outlined,
                          size: 40, color: cs.outline),
                      const SizedBox(height: 8),
                      Text(
                        'No hay categorías registradas.\nCrea la primera con el botón +.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
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
                        icon: Icon(Icons.edit, color: cs.primary),
                        onPressed: () => _editarCategoria(cat),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: cs.error),
                        onPressed: () => _eliminarCategoria(cat),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}
