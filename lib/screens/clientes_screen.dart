import 'package:flutter/material.dart';

import '../models/cliente_model.dart';
import '../services/api_service.dart';
import '../widgets/cliente_dialog.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  List<ClienteModel> _clientes = [];
  bool _isLoading = true;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getClientes();
      setState(() {
        _clientes = res;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar clientes: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _abrirDialogoCliente([ClienteModel? cliente]) async {
    final res = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteDialog(cliente: cliente),
    );
    if (res != null) {
      _cargarClientes();
    }
  }

  Future<void> _eliminarCliente(ClienteModel cliente) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Eliminar el cliente "${cliente.nombreRazonSocial}"?'),
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

    if (confirm == true && cliente.clienteId != null) {
      final res = await ApiService.deleteCliente(cliente.clienteId!);
      if (mounted) {
        if (res['success'] == true) {
          _cargarClientes();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: ${res['error']}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientesFiltrados = _clientes.where((c) {
      final query = _filtro.toLowerCase();
      final docCompleto = '${c.tipoDocumento}-${c.numDocumento}'.toLowerCase();
      return c.nombreRazonSocial.toLowerCase().contains(query) ||
          docCompleto.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Clientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarClientes,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por Nombre o RIF/Cédula...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _filtro = val),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : clientesFiltrados.isEmpty
                  ? const Center(child: Text('No se encontraron clientes.'))
                  : ListView.builder(
                      itemCount: clientesFiltrados.length,
                      itemBuilder: (context, index) {
                        final cliente = clientesFiltrados[index];
                        return Card(
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                cliente.nombreRazonSocial.isNotEmpty
                                    ? cliente.nombreRazonSocial[0].toUpperCase()
                                    : 'C',
                              ),
                            ),
                            title: Text(
                              cliente.nombreRazonSocial,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${cliente.tipoDocumento}-${cliente.numDocumento} | Tel: ${cliente.telefono ?? "N/A"}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _abrirDialogoCliente(cliente),
                                ),
                                if (cliente.clienteId != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _eliminarCliente(cliente),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirDialogoCliente(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
