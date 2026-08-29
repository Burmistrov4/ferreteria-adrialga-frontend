import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';

class ProductoDialog extends StatefulWidget {
  final ProductoModel? producto;
  final List<CategoriaModel> categorias;

  const ProductoDialog({super.key, this.producto, required this.categorias});

  @override
  State<ProductoDialog> createState() => _ProductoDialogState();
}

class _ProductoDialogState extends State<ProductoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _skuController;
  late TextEditingController _nombreController;
  late TextEditingController _descripcionController;
  late TextEditingController _precioController;
  late TextEditingController _costoController;
  late TextEditingController _stockActualController;
  late TextEditingController _stockMinimoController;
  int? _selectedCategoriaId;

  @override
  void initState() {
    super.initState();
    _skuController = TextEditingController(
      text: widget.producto?.skuCodigo ?? '',
    );
    _nombreController = TextEditingController(
      text: widget.producto?.nombre ?? '',
    );
    _descripcionController = TextEditingController(
      text: widget.producto?.descripcion ?? '',
    );
    _precioController = TextEditingController(
      text: widget.producto?.precioVenta.toString() ?? '0.00',
    );
    _costoController = TextEditingController(
      text: widget.producto?.costoPromedio.toString() ?? '0.00',
    );
    _stockActualController = TextEditingController(
      text: widget.producto?.stockActual.toString() ?? '0',
    );
    _stockMinimoController = TextEditingController(
      text: widget.producto?.stockMinimo.toString() ?? '5',
    );
    final idsCategorias = widget.categorias.map((c) => c.categoriaId).toSet();
    final categoriaProducto = widget.producto?.categoriaId;
    _selectedCategoriaId =
        (categoriaProducto != null && idsCategorias.contains(categoriaProducto))
            ? categoriaProducto
            : (widget.categorias.isNotEmpty
                ? widget.categorias.first.categoriaId
                : null);
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _precioController.dispose();
    _costoController.dispose();
    _stockActualController.dispose();
    _stockMinimoController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'SKU_Codigo': _skuController.text.trim(),
        'Nombre': _nombreController.text.trim(),
        'Descripcion': _descripcionController.text.trim(),
        'Precio_Venta': double.tryParse(_precioController.text) ?? 0.0,
        'Costo_Promedio': double.tryParse(_costoController.text) ?? 0.0,
        'Stock_Actual': int.tryParse(_stockActualController.text) ?? 0,
        'Stock_Minimo': int.tryParse(_stockMinimoController.text) ?? 5,
        'Categoria_ID': _selectedCategoriaId,
      };
      Navigator.of(context).pop(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.producto != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar Producto' : 'Nuevo Producto'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _skuController,
                decoration: const InputDecoration(labelText: 'SKU / Código *'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _descripcionController,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              DropdownButtonFormField<int>(
                value: _selectedCategoriaId,
                decoration: const InputDecoration(labelText: 'Categoría *'),
                items: widget.categorias.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat.categoriaId,
                    child: Text(cat.nombreCategoria),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCategoriaId = val),
                validator: (val) =>
                    val == null ? 'Seleccione una categoría' : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _precioController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio Venta (\$)*',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _costoController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Costo Promedio (\$)',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockActualController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stock Actual *',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _stockMinimoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stock Mínimo',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: Text(
            isEditing ? 'Actualizar' : 'Guardar',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
