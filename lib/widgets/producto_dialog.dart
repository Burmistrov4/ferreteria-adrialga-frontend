import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../services/api_service.dart';

class ProductoDialog extends StatefulWidget {
  final ProductoModel? producto;
  final List<CategoriaModel> categorias;
  final void Function(CategoriaModel categoria)? onCategoriaCreada;

  const ProductoDialog({
    super.key,
    this.producto,
    required this.categorias,
    this.onCategoriaCreada,
  });

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
  late TextEditingController _margenController;
  late List<CategoriaModel> _categorias;
  int? _selectedCategoriaId;

  /// Bandera anti-recursión: mientras un listener de costo/margen actualiza
  /// el precio (o viceversa), se evita que el listener del objetivo dispare
  /// un segundo cálculo (overflow de pila por escritura cíclica).
  bool _calculando = false;

  @override
  void initState() {
    super.initState();
    _categorias = List.of(widget.categorias);
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
      text: widget.producto?.costoUltimo.toString() ??
          widget.producto?.costoPromedio.toString() ??
          '0.00',
    );
    _margenController = TextEditingController(
      text: widget.producto?.margenGanancia.toString() ?? '0.0',
    );
    _stockActualController = TextEditingController(
      text: widget.producto?.stockActual.toString() ?? '0',
    );
    _stockMinimoController = TextEditingController(
      text: widget.producto?.stockMinimo.toString() ?? '5',
    );
    final idsCategorias = _categorias.map((c) => c.categoriaId).toSet();
    final categoriaProducto = widget.producto?.categoriaId;
    _selectedCategoriaId =
        (categoriaProducto != null && idsCategorias.contains(categoriaProducto))
            ? categoriaProducto
            : (_categorias.isNotEmpty
                ? _categorias.first.categoriaId
                : null);

    // Reactividad precio ⇄ margen: al editar costo o margen se recalcula el
    // precio sugerido; al editar el precio directo se deriva el margen.
    _costoController.addListener(_recalcularPrecioDesdeCostoMargen);
    _margenController.addListener(_recalcularPrecioDesdeCostoMargen);
    _precioController.addListener(_recalcularMargenDesdePrecio);
  }

  double get _costo => double.tryParse(_costoController.text.replaceAll(',', '.')) ?? 0;
  double get _margen => double.tryParse(_margenController.text.replaceAll(',', '.')) ?? 0;
  double get _precio => double.tryParse(_precioController.text.replaceAll(',', '.')) ?? 0;

  void _setText(TextEditingController c, String t) {
    c.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  static String _fmt(double v) => v.toStringAsFixed(2);

  void _recalcularPrecioDesdeCostoMargen() {
    if (_calculando) return;
    _calculando = true;
    try {
      if (_costo > 0) {
        _setText(_precioController, _fmt(_costo * (1 + _margen / 100)));
      }
    } finally {
      _calculando = false;
    }
  }

  void _recalcularMargenDesdePrecio() {
    if (_calculando) return;
    _calculando = true;
    try {
      if (_costo > 0 && _precio > 0) {
        _setText(_margenController, _fmt((_precio / _costo - 1) * 100));
      }
    } finally {
      _calculando = false;
    }
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _precioController.dispose();
    _costoController.dispose();
    _margenController.dispose();
    _stockActualController.dispose();
    _stockMinimoController.dispose();
    super.dispose();
  }

  /// Crea una categoría nueva "en línea" desde el formulario de producto,
  /// sin salir del diálogo. Tras crearla, la agrega a la lista local, la
  /// selecciona y notifica al padre para que sincronice su estado.
  Future<void> _crearCategoriaInline() async {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final confirmada = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Nueva Categoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              autofocus: true,
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
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Cierre de ciclo: no puede crearse una categoría sin nombre.
              // Se notifica en línea en vez de fallar en silencio.
              if (nombreCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(content: Text('Escribe el nombre de la categoría')),
                );
                return;
              }
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (confirmada == true && nombreCtrl.text.trim().isNotEmpty) {
      final nueva = await ApiService.createCategoriaConRetorno(
        nombreCtrl.text.trim(),
        descCtrl.text.trim(),
      );
      if (nueva != null && mounted) {
        setState(() {
          _categorias.add(nueva);
          _selectedCategoriaId = nueva.categoriaId;
        });
        widget.onCategoriaCreada?.call(nueva);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Categoría "${nueva.nombreCategoria}" creada'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ApiService.ultimoErrorCategoria ??
                'Error al crear la categoría'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    nombreCtrl.dispose();
    descCtrl.dispose();
  }

  /// Validadores numéricos: bloquean precios <= 0 y cantidades no numéricas
  /// antes de tocar la API (evita productos creados con datos incoherentes).
  String? _validarNumero(String? v, {required bool obligatorioPositivo}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Requerido';
    final n = double.tryParse(t);
    if (n == null) return 'Ingrese un número válido';
    if (n < 0) return 'No puede ser negativo';
    if (obligatorioPositivo && n <= 0) return 'Debe ser mayor a 0';
    return null;
  }

  String? _validarEntero(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Requerido';
    final n = int.tryParse(t);
    if (n == null) return 'Ingrese un número entero';
    if (n < 0) return 'No puede ser negativo';
    return null;
  }

  void _guardar() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'SKU_Codigo': _skuController.text.trim(),
        'Nombre': _nombreController.text.trim(),
        'Descripcion': _descripcionController.text.trim(),
        'Precio_Venta': _precio,
        'Costo_Promedio': _costo,
        'Costo_Ultimo': _costo,
        'Margen_Ganancia': _margen,
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
      content: LayoutBuilder(
        builder: (context, constraints) {
          final dosCol = constraints.maxWidth >= 600;
          final cs = Theme.of(context).colorScheme;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU / Código *',
                    ),
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                    ),
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: _descripcionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedCategoriaId,
                          decoration: const InputDecoration(
                            labelText: 'Categoría *',
                          ),
                          items: _categorias.map((cat) {
                            return DropdownMenuItem<int>(
                              value: cat.categoriaId,
                              child: Text(cat.nombreCategoria),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _selectedCategoriaId = val),
                          validator: (val) =>
                              val == null ? 'Seleccione una categoría' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: IconButton(
                          tooltip: 'Crear nueva categoría',
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          onPressed: _crearCategoriaInline,
                          icon: Icon(Icons.add, color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                  // Responsive: en tablet/desktop dos columnas; en móvil apilados.
                  if (dosCol) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _costoController,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) =>
                                _validarNumero(v, obligatorioPositivo: false),
                            decoration: const InputDecoration(
                              labelText: 'Costo de compra (\$)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _margenController,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) =>
                                _validarNumero(v, obligatorioPositivo: false),
                            decoration: const InputDecoration(
                              labelText: 'Margen %',
                              helperText: 'Sobre el costo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _precioController,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) =>
                                _validarNumero(v, obligatorioPositivo: true),
                            decoration: const InputDecoration(
                              labelText: 'Precio Venta (\$)*',
                              helperText: 'Precio = Costo × (1 + Margen)',
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
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: _validarEntero,
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
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: _validarEntero,
                            decoration: const InputDecoration(
                              labelText: 'Stock Mínimo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _precioController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          _validarNumero(v, obligatorioPositivo: true),
                      decoration: const InputDecoration(
                        labelText: 'Precio Venta (\$)*',
                        helperText: 'Precio = Costo × (1 + Margen)',
                      ),
                    ),
                    TextFormField(
                      controller: _costoController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          _validarNumero(v, obligatorioPositivo: false),
                      decoration: const InputDecoration(
                        labelText: 'Costo de compra (\$)',
                      ),
                    ),
                    TextFormField(
                      controller: _margenController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          _validarNumero(v, obligatorioPositivo: false),
                      decoration: const InputDecoration(
                        labelText: 'Margen %',
                        helperText: 'Sobre el costo',
                      ),
                    ),
                    TextFormField(
                      controller: _stockActualController,
                      keyboardType: TextInputType.number,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: _validarEntero,
                      decoration: const InputDecoration(
                        labelText: 'Stock Actual *',
                      ),
                    ),
                    TextFormField(
                      controller: _stockMinimoController,
                      keyboardType: TextInputType.number,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: _validarEntero,
                      decoration: const InputDecoration(
                        labelText: 'Stock Mínimo',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          child: Text(isEditing ? 'Actualizar' : 'Guardar'),
        ),
      ],
    );
  }
}
