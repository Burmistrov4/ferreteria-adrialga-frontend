import 'package:flutter/material.dart';

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

  Future<void> _crearProveedor() async {
    final rifCtrl = TextEditingController();
    final razonCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();

    final okGuardar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo Proveedor'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: rifCtrl,
                  decoration: const InputDecoration(labelText: 'RIF *'),
                ),
                TextField(
                  controller: razonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Razón Social *',
                  ),
                ),
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                  ),
                ),
                TextField(
                  controller: direccionCtrl,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
              ],
            ),
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

    if (okGuardar == true) {
      if (rifCtrl.text.trim().isEmpty || razonCtrl.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('RIF y Razón Social son obligatorios'),
            ),
          );
        }
        return;
      }
      final res = await ApiService.createProveedor({
        'RIF_Cedula': rifCtrl.text.trim(),
        'Razon_Social': razonCtrl.text.trim(),
        'Telefono': telCtrl.text.trim().isEmpty ? null : telCtrl.text.trim(),
        'Email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        'Direccion': direccionCtrl.text.trim().isEmpty
            ? null
            : direccionCtrl.text.trim(),
      });
      if (mounted) {
        if (res['success'] == true) {
          _cargarProveedores();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proveedor creado exitosamente')),
          );
        } else {
          final cs = Theme.of(context).colorScheme;
          final detalle = res['error']?.toString().trim() ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                detalle.isEmpty
                    ? 'Error al crear proveedor'
                    : 'Error al crear proveedor: $detalle',
              ),
              backgroundColor: cs.error,
            ),
          );
        }
      }
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
                    ),
                  );
                },
              ),
      ),
    );
  }
}
