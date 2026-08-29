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
      setState(() {
        _proveedores = res;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
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
                  decoration: const InputDecoration(labelText: 'Correo'),
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al crear proveedor: ${res['error']}'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarProveedores,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearProveedor,
        backgroundColor: Colors.indigo,
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
                final prov = _proveedores[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.local_shipping,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      prov['Razon_Social'] ?? 'Sin Nombre',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'RIF: ${prov['RIF_Cedula'] ?? "N/A"} | Tel: '
                      '${prov['Telefono'] ?? "N/A"}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
