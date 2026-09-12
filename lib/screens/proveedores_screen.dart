import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  List<dynamic> _proveedores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
  }

  Future<void> _cargarProveedores() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getProveedores();
      if (mounted) {
        setState(() {
          _proveedores = res;
        });
      }
    } catch (e) {
      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar proveedores: $e'),
            backgroundColor: cs.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _crearProveedor() => _mostrarDialogoProveedor();

  Future<void> _editarProveedor(Map<String, dynamic> prov) =>
      _mostrarDialogoProveedor(proveedor: prov);

  Future<void> _mostrarDialogoProveedor({Map<String, dynamic>? proveedor}) async {
    final editando = proveedor != null;
    final rifCtrl = TextEditingController(
        text: proveedor?['RIF_Cedula']?.toString() ?? '');
    final razonCtrl = TextEditingController(
        text: proveedor?['Razon_Social']?.toString() ?? '');
    final telCtrl = TextEditingController(
        text: proveedor?['Telefono']?.toString() ?? '');
    final emailCtrl = TextEditingController(
        text: proveedor?['Email']?.toString() ?? '');
    final direccionCtrl = TextEditingController(
        text: proveedor?['Direccion']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final okGuardar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(editando ? 'Editar Proveedor' : 'Nuevo Proveedor'),
        // Diálogo elástico (responsive): en móvil ocupa hasta el 90% del
        // ancho; en escritorio se limita a 480. Con SingleChildScrollView
        // para que el teclado/espacio vertical nunca desborde.
        content: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth.isFinite &&
                    constraints.maxWidth < 480
                ? constraints.maxWidth
                : 480.0;
            return SizedBox(
              width: ancho,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: rifCtrl,
                        // El RIF es inmutable: es la clave fiscal del proveedor.
                        enabled: !editando,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[VEJPGRvejpg\-0-9]'),
                          ),
                          TextInputFormatter.withFunction((oldValue, newValue) =>
                              newValue.copyWith(
                                  text: newValue.text.toUpperCase())),
                        ],
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: _validarRif,
                        decoration: const InputDecoration(
                          labelText: 'RIF *',
                          hintText: 'J-12345678-9',
                        ),
                      ),
                      TextFormField(
                        controller: razonCtrl,
                        textCapitalization: TextCapitalization.characters,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'La Razón Social es obligatoria'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Razón Social *',
                        ),
                      ),
                      TextFormField(
                        controller: telCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Teléfono'),
                      ),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo Electrónico',
                        ),
                      ),
                      TextFormField(
                        controller: direccionCtrl,
                        decoration: const InputDecoration(labelText: 'Dirección'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (okGuardar == true) {
      final res = editando
          ? await ApiService.updateProveedor(
              (proveedor['Proveedor_ID'] as num).toInt(),
              {
                'Razon_Social': razonCtrl.text.trim(),
                'Telefono':
                    telCtrl.text.trim().isEmpty ? null : telCtrl.text.trim(),
                'Email': emailCtrl.text.trim().isEmpty
                    ? null
                    : emailCtrl.text.trim(),
                'Direccion': direccionCtrl.text.trim().isEmpty
                    ? null
                    : direccionCtrl.text.trim(),
              },
            )
          : await ApiService.createProveedor({
              'RIF_Cedula': rifCtrl.text.trim(),
              'Razon_Social': razonCtrl.text.trim(),
              'Telefono':
                  telCtrl.text.trim().isEmpty ? null : telCtrl.text.trim(),
              'Email':
                  emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
              'Direccion': direccionCtrl.text.trim().isEmpty
                  ? null
                  : direccionCtrl.text.trim(),
            });
      if (mounted) {
        if (res['success'] == true) {
          _cargarProveedores();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(editando
                    ? 'Proveedor actualizado'
                    : 'Proveedor creado exitosamente'),
              ),
            );
          }
        } else {
          final cs = Theme.of(context).colorScheme;
          final detalle = res['error']?.toString().trim() ?? '';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  detalle.isEmpty
                      ? 'Error al guardar proveedor'
                      : 'Error al guardar proveedor: $detalle',
                ),
                backgroundColor: cs.error,
              ),
            );
          }
        }
      }
    }
    // Saneamiento: libero los controladores tras el diálogo para no acumular
    // listeners (bloqueo del hilo) al abrir/cerrar repetidamente.
    rifCtrl.dispose();
    razonCtrl.dispose();
    telCtrl.dispose();
    emailCtrl.dispose();
    direccionCtrl.dispose();
  }

  /// Elimina un proveedor con confirmación explícita. El backend rechaza la
  /// operación (409) si tiene compras o cuentas por pagar pendientes.
  Future<void> _confirmarEliminar(Map<String, dynamic> prov) async {
    final razon = prov['Razon_Social']?.toString() ?? 'este proveedor';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar proveedor'),
        content: Text(
          '¿Eliminar a "$razon"? Solo es posible si no tiene compras ni deudas pendientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    final res = await ApiService.deleteProveedor(
        (prov['Proveedor_ID'] as num).toInt());
    if (!mounted) return;
    if (res['success'] == true) {
      _cargarProveedores();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proveedor eliminado')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'No se pudo eliminar'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Validación fiscal de RIF de proveedor `^([VEJPG]-)?\d{7,9}$`:
  /// prefijo V/E/J/G/P opcional + 7 a 9 dígitos.
  String? _validarRif(String? valor) {
    final v = (valor ?? '').trim().toUpperCase();
    if (v.isEmpty) return 'El RIF es obligatorio';
    final body = v.startsWith(RegExp(r'[VEJPG]-'))
        ? v.substring(2)
        : v.replaceAll('-', '');
    if (body.length < 7 || body.length > 9 || !RegExp(r'^\d+$').hasMatch(body)) {
      return 'RIF inválido: use prefijo (V/E/J/G) y 7 a 9 dígitos';
    }
    return null;
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
          title: const Text('Proveedores'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cargarProveedores,
              tooltip: 'Actualizar',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _crearProveedor,
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          tooltip: 'Nuevo Proveedor',
          child: const Icon(Icons.add),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _proveedores.isEmpty
            ? const Center(child: Text('No hay proveedores registrados.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _proveedores.length,
                itemBuilder: (context, index) {
                  final prov = _proveedores[index] as Map<String, dynamic>;
                  final rif = prov['RIF_Cedula']?.toString() ?? 'S/R';
                  final razon =
                      prov['Razon_Social']?.toString() ?? 'Sin Nombre';
                  final telefono = prov['Telefono']?.toString() ?? 'N/A';
                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Icon(
                          Icons.local_shipping,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        razon,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('RIF: $rif | Tel: $telefono'),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar',
                            onPressed: () => _editarProveedor(prov),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            tooltip: 'Eliminar',
                            onPressed: () => _confirmarEliminar(prov),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
