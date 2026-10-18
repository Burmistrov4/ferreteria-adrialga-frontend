import 'package:flutter/material.dart';

import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../services/api_service.dart';
import '../services/configuracion_service.dart';
import 'variantes_tab.dart';

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
  late TextEditingController _imagenController;
  late List<CategoriaModel> _categorias;
  int? _selectedCategoriaId;

  /// Bandera anti-recursión: mientras un listener de costo/margen actualiza
  /// el precio (o viceversa), se evita que el listener del objetivo dispare
  /// un segundo cálculo (overflow de pila por escritura cíclica).
  bool _calculando = false;

  /// Agencia del usuario: true cuando el usuario editó el margen a mano;
  /// evita que la inyección automática le pise su elección.
  bool _margenEditadoManual = false;

  /// Margen efectivo al abrir el formulario: cascada Producto > Categoría > Global.
  double? _margenInicialSugerido;

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
    _imagenController = TextEditingController(
      text: widget.producto?.imagenUrl?.toString() ?? '',
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
    // Campo vacío o cero = "aplica cascada" (Margen Defecto de Configuración).
    _margenController.addListener(() {
      // Detectar si el usuario modificó el campo margen manualmente.
      // (es el único listener del campo que no lleva _calculando)
      final limpio = _margenController.text.trim();
      if (limpio.isNotEmpty &&
          limpio != (_margenInicialSugerido?.toStringAsFixed(2) ?? '') &&
          limpio != (widget.producto?.margenGanancia.toStringAsFixed(2) ?? '0.00')) {
        _margenEditadoManual = true;
      }
      _recalcularPrecioDesdeCostoMargen();
    });
    _precioController.addListener(_recalcularMargenDesdePrecio);

    // Regla inicial: cascada Producto > Categoría > Config. Solo nuevo.
    if (widget.producto == null && _margen == 0) {
      _aplicarMargenPorCascada();
    }
  }

  /// Inyección automática del margen por cascada (solo si el usuario aún no
  /// toca el campo de margen). Categoría > Configuración global.
  Future<void> _aplicarMargenPorCascada() async {
    if (_margenEditadoManual) return;
    // 1. Categoría
    final catId = _selectedCategoriaId;
    if (catId != null) {
      final cat = _categorias
          .where((c) => c.categoriaId == catId)
          .firstOrNull;
      final ms = cat?.margenSugerido;
      if (ms != null && ms > 0) {
        // Sin setState: el texto se escribe directamente en el controller
        // (es una entrada solitaria, el setState lo dispara el listener).
        _margenController.text = ms.toStringAsFixed(2);
        _margenInicialSugerido = ms;
        return;
      }
    }
    // 2. Global de tienda
    try {
      final cfg = await ConfiguracionService.obtener();
      if (!mounted || cfg.margenDefecto <= 0) return;
      _margenController.text = cfg.margenDefecto.toStringAsFixed(2);
      _margenInicialSugerido = cfg.margenDefecto;
    } catch (_) {}
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
    _imagenController.dispose();
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

  /// SKU automático por categoría: inyecta el prefijo (`cat.prefijoSku`) en
  /// el controller del SKU cuando el campo está vacío o todavía contiene el
  /// prefijo de otra categoría (el usuario aún no lo personalizó).
  void _aplicarPrefijoSku(CategoriaModel cat) {
    final actual = _skuController.text.trim();
    final esAutomatico = actual.isEmpty ||
        _categorias.any((c) =>
            c.prefijoSku != null &&
            c.prefijoSku!.isNotEmpty &&
            actual == c.prefijoSku!.trim());
    if (esAutomatico) {
      _skuController.text = cat.prefijoSku ?? '';
    }
  }

  /// Selector de categoría en hoja inferior: usable en móvil (el Autocomplete
  /// anterior reiniciaba el texto en cada rebuild y se solapaba al teclado).
  /// Incluye búsqueda local y respeta la selección previa.
  Future<void> _seleccionarCategoria() async {
    final busquedaCtrl = TextEditingController();
    String query = '';
    final seleccionada = await showModalBottomSheet<CategoriaModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtradas = query.isEmpty
                ? _categorias
                : _categorias
                    .where((c) =>
                        c.nombreCategoria.toLowerCase().contains(query))
                    .toList();
            return SafeArea(
              child: Padding(
                // La hoja sube con el teclado de la búsqueda.
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.6,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: busquedaCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Buscar categoría',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setSheetState(
                            () => query = v.toLowerCase().trim(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filtradas.isEmpty
                            ? Center(
                                child: Text(
                                  'Sin coincidencias',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                            : ListView.builder(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: filtradas.length,
                                itemBuilder: (_, i) {
                                  final cat = filtradas[i];
                                  final activa =
                                      cat.categoriaId == _selectedCategoriaId;
                                  return ListTile(
                                    title: Text(cat.nombreCategoria),
                                    subtitle:
                                        (cat.prefijoSku?.isNotEmpty ?? false)
                                            ? Text(
                                                'SKU base: ${cat.prefijoSku}')
                                            : null,
                                    trailing: activa
                                        ? Icon(Icons.check_circle,
                                            color: cs.primary)
                                        : null,
                                    selected: activa,
                                    onTap: () => Navigator.pop(sheetCtx, cat),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    busquedaCtrl.dispose();

    if (seleccionada == null || !mounted) return;
    setState(() => _selectedCategoriaId = seleccionada.categoriaId);
    _aplicarPrefijoSku(seleccionada);
    // Cascada por categoría: aplica SOLO si el usuario no editó el margen.
    final ms = seleccionada.margenSugerido;
    if (ms != null && ms > 0 && !_margenEditadoManual) {
      _margenController.text = ms.toStringAsFixed(2);
      _margenInicialSugerido = ms;
      _recalcularPrecioDesdeCostoMargen();
    }
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
        'Imagen_URL': _imagenController.text.trim().isEmpty
            ? null
            : _imagenController.text.trim(),
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
    // ANTI-FREEZE (Fase 1): este contenido se usa como `content:` de un
    // `AlertDialog`, que lo mide con `IntrinsicWidth`
    // (flutter/.../material/dialog.dart:925). Un `LayoutBuilder` NO soporta
    // dimensiones intrínsecas: lanza `FlutterError("LayoutBuilder does not
    // support returning intrinsic dimensions")` durante el build y deja el
    // diálogo sin dibujar sobre la barrera modal opaca.
    // El breakpoint se deriva del viewport (estable) en vez del layout padre.
    // `Builder` sí es seguro: no interviene en el layout, solo aporta `context`.
    final anchoPantalla = MediaQuery.of(context).size.width;
    final anchoContenido = anchoPantalla < 560 ? anchoPantalla - 56 : 560.0;
    final dosCol = anchoContenido >= 600;
    final generalContent = Builder(
      builder: (innerCtx) {
        final cs = Theme.of(innerCtx).colorScheme;
        return SingleChildScrollView(
          // Compensa el teclado virtual: el formulario queda desplazable
          // sobre el IME en móvil (sin "saltos" del layout al escribir).
          // `top: 12` separa el primer campo del TabBar para que la etiqueta
          // flotante del SKU no se monte sobre la pestaña activa.
          padding: EdgeInsets.only(
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
            key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // Separación uniforme: sin esto las etiquetas flotantes de
                // cada campo se montaban sobre el campo anterior (se veían
                // solapadas en la pestaña "Datos Generales").
                spacing: 12,
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
                  TextField(
                    controller: _descripcionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                    ),
                  ),
                  TextField(
                    controller: _imagenController,
                    decoration: const InputDecoration(
                      labelText: 'URL de la imagen (opcional)',
                      hintText: 'https://ejemplo.com/foto.jpg',
                    ),
                  ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          // Selector de categoría por hoja inferior (móvil OK):
                          // campo readOnly que abre _seleccionarCategoria con
                          // buscador; al elegirse autogenera el prefijo del SKU.
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: _seleccionarCategoria,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Categoría *',
                                border: const OutlineInputBorder(),
                                suffixIcon: Icon(Icons.arrow_drop_down,
                                    color: cs.onSurfaceVariant),
                              ),
                              child: Text(
                                _categorias
                                        .where((c) =>
                                            c.categoriaId == _selectedCategoriaId)
                                        .firstOrNull
                                        ?.nombreCategoria ??
                                    'Seleccionar categoría…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _selectedCategoriaId == null
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                              ),
                            ),
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
    );

    // En edición el diálogo se bifurca en 2 pestañas sin romper el alta
    // rápida de un producto nuevo (que no tiene ID hasta guardarse).
    if (!isEditing) {
      return AlertDialog(
        title: const Text('Nuevo Producto'),
        content: generalContent,
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
            child: const Text('Guardar'),
          ),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(isEditing ? 'Editar Producto' : 'Nuevo Producto'),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: DefaultTabController(
        length: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: cs.primary,
              tabs: const [
                Tab(text: 'Datos Generales'),
                Tab(text: 'Variantes'),
              ],
            ),
            // Altura adaptativa a la pantalla: en móviles un SizedBox fijo de
            // 420px desborda el AlertDialog (BOTTOM OVERFLOWED BY ~20px). Se
            // usa un % de la altura disponible para que el diálogo quepa con
            // teclado y sin recortar las pestañas. El contenido interno
            // (generalContent / VariantesTab) ya es scrollable por sí mismo.
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              // El ancho máximo se acota en pantallas táctiles
              // (<560) para evitar overflows del TabBarView.
              width: MediaQuery.of(context).size.width < 560
                  ? MediaQuery.of(context).size.width - 56
                  : 560,
              child: TabBarView(
                children: [
                  generalContent,
                  if (isEditing)
                    VariantesTab(
                      producto: widget.producto!,
                      onGuardado: () {}, // backend refresca al cerrar
                    )
                  else
                    Center(
                      child: Text(
                        'Guarda el producto primero para poder crear variantes.',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
          child: Text(isEditing ? 'Actualizar' : 'Guardar'),
        ),
      ],
    );
  }
}
