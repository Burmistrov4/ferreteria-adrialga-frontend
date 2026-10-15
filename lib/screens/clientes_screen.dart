import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cliente_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/responsive.dart';
import '../widgets/cliente_dialog.dart';
import '../widgets/hover_tile.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  List<ClienteModel> _clientes = [];
  bool _isLoading = true;
  String _filtro = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
    SocketService.onDbUpdateModulo(_alDbUpdate);
  }

  @override
  void dispose() {
    SocketService.offDbUpdateModulo(_alDbUpdate);
    _debounce?.cancel();
    super.dispose();
  }

  void _alDbUpdate(String modulo) {
    if (!mounted || (modulo != 'clientes' && modulo != '__reconexion__'))
      return;
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    setState(() => _isLoading = true);
    try {
      // Búsqueda server-side: el backend filtra por Nombre / Razón Social,
      // RIF o número de documento con un OR en Prisma.
      final res = await ApiService.getClientes(_filtro);
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

  void _onFiltroChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _cargarClientes);
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
    final cs = Theme.of(context).colorScheme;
    final clientesFiltrados = _clientes.where((c) {
      final query = _filtro.toLowerCase();
      final docCompleto = '${c.tipoDocumento}-${c.numDocumento}'.toLowerCase();
      return c.nombreRazonSocial.toLowerCase().contains(query) ||
          docCompleto.contains(query);
    }).toList();

    return SafeArea(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text('Gestión de Clientes'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              color: cs.onPrimary,
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
                onChanged: (val) {
                  _filtro = val;
                  _onFiltroChanged(val);
                },
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
                            child: HoverTile(
                              onTap: () => _abrirDialogoCliente(cliente),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    cliente.nombreRazonSocial.isNotEmpty
                                        ? cliente.nombreRazonSocial[0]
                                              .toUpperCase()
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
                                trailing:
                                    AdrialgaResponsive.isMobile(
                                      MediaQuery.sizeOf(context).width,
                                    )
                                    ? PopupMenuButton<String>(
                                        tooltip: 'Acciones del cliente',
                                        onSelected: (value) {
                                          if (value == 'editar')
                                            _abrirDialogoCliente(cliente);
                                          if (value == 'eliminar')
                                            _eliminarCliente(cliente);
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'editar',
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.edit),
                                              title: Text('Editar cliente'),
                                            ),
                                          ),
                                          if (cliente.clienteId != null)
                                            const PopupMenuItem(
                                              value: 'eliminar',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(Icons.delete),
                                                title: Text('Eliminar cliente'),
                                              ),
                                            ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            constraints: const BoxConstraints(
                                              minWidth: 48,
                                              minHeight: 48,
                                            ),
                                            icon: Icon(
                                              Icons.edit,
                                              color: cs.primary,
                                            ),
                                            tooltip: 'Editar cliente',
                                            onPressed: () =>
                                                _abrirDialogoCliente(cliente),
                                          ),
                                          if (cliente.clienteId != null)
                                            IconButton(
                                              constraints: const BoxConstraints(
                                                minWidth: 48,
                                                minHeight: 48,
                                              ),
                                              icon: Icon(
                                                Icons.delete,
                                                color: cs.error,
                                              ),
                                              tooltip: 'Eliminar cliente',
                                              onPressed: () =>
                                                  _eliminarCliente(cliente),
                                            ),
                                        ],
                                      ),
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
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          onPressed: () => _abrirDialogoCliente(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
