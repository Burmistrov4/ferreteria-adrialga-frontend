import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente_model.dart';
import '../services/api_service.dart';

class ClienteDialog extends StatefulWidget {
  final ClienteModel? cliente;

  const ClienteDialog({super.key, this.cliente});

  @override
  State<ClienteDialog> createState() => _ClienteDialogState();
}

class _ClienteDialogState extends State<ClienteDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _searchDocController = TextEditingController();
  bool _isSearching = false;
  // Búsqueda flexible en tiempo real (nombre, RIF o cédula) con debounce
  // de 350 ms para no golpear la API en cada tecla.
  List<ClienteModel> _resultados = [];
  // Últimos clientes precargados al abrir el diálogo (autoload Fase 2): la
  // lista nunca inicia vacía y se restaura cuando se limpia la búsqueda.
  List<ClienteModel> _recientes = [];
  bool _mostrandoRecientes = true;
  Timer? _debounce;

  // Naturaleza del documento: 'cedula' (Persona Natural) o 'rif' (Jurídico /
  // Pasaporte). El dropdown de prefijos se filtra según esta selección.
  String _grupoDoc = 'cedula';
  static const Map<String, List<String>> _prefijosPorGrupo = {
    'cedula': ['V', 'E'],
    'rif': ['J', 'G', 'P'],
  };

  String _tipoDoc = 'V';
  final _numDocController = TextEditingController();
  final _nombreController = TextEditingController();
  final _direccionController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isConsultingSeniat = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _cargarRecientes();

    if (widget.cliente != null) {
      _tipoDoc = widget.cliente!.tipoDocumento;
      _grupoDoc = (_prefijosPorGrupo['cedula']!.contains(_tipoDoc))
          ? 'cedula'
          : 'rif';
      _numDocController.text = widget.cliente!.numDocumento;
      _nombreController.text = widget.cliente!.nombreRazonSocial;
      _direccionController.text = widget.cliente!.direccion ?? '';
      _telefonoController.text = widget.cliente!.telefono ?? '';
      _emailController.text = widget.cliente!.email ?? '';
      _tabController.index = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDocController.dispose();
    _numDocController.dispose();
    _nombreController.dispose();
    _direccionController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Autoload: carga los últimos 10 clientes registrados para que la lista
  /// no inicie vacía al abrir el diálogo.
  Future<void> _cargarRecientes() async {
    final recientes = await ApiService.getUltimosClientes(10);
    if (!mounted) return;
    setState(() {
      _recientes = recientes;
      // Solo se muestran como autoload si aún no hay búsqueda activa.
      if (_searchDocController.text.trim().isEmpty) {
        _resultados = recientes;
        _mostrandoRecientes = true;
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _resultados = _recientes;
        _mostrandoRecientes = true;
        _isSearching = false;
      });
      return;
    }
    _mostrandoRecientes = false;
    _debounce = Timer(const Duration(milliseconds: 350), _buscarClienteLocal);
  }

  Future<void> _buscarClienteLocal() async {
    final query = _searchDocController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    final clientes = await ApiService.buscarClientes(query);
    if (!mounted) return;
    setState(() {
      _resultados = clientes;
      _isSearching = false;
    });

    if (clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cliente no encontrado localmente. Utilice el registro SENIAT o Manual.',
          ),
        ),
      );
    }
  }

  Future<void> _consultarSeniat() async {
    final numDoc = _numDocController.text.trim();
    if (numDoc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el número de Cédula o RIF')),
      );
      return;
    }

    setState(() => _isConsultingSeniat = true);
    final res = await ApiService.consultarSeniat(_tipoDoc, numDoc);
    setState(() => _isConsultingSeniat = false);

    if (res['success'] == true) {
      setState(() {
        _nombreController.text = res['nombre'] ?? '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Datos del SENIAT cargados correctamente!'),
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error'] ?? 'No se halló información en SENIAT'),
        ),
      );
    }
  }

  Future<void> _guardarYSeleccionar() async {
    if (_numDocController.text.isEmpty || _nombreController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Número de Documento y Nombre son obligatorios'),
        ),
      );
      return;
    }

    final nuevoCliente = ClienteModel(
      clienteId: widget.cliente?.clienteId,
      tipoDocumento: _tipoDoc,
      numDocumento: _numDocController.text.trim(),
      nombreRazonSocial: _nombreController.text.trim(),
      direccion: _direccionController.text.trim().isEmpty
          ? null
          : _direccionController.text.trim(),
      telefono: _telefonoController.text.trim().isEmpty
          ? null
          : _telefonoController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
    );

    setState(() => _isSaving = true);

    final Map<String, dynamic> res;
    final bool esEdicion = widget.cliente?.clienteId != null;

    if (esEdicion) {
      res = await ApiService.updateCliente(
        widget.cliente!.clienteId!,
        nuevoCliente.toJson(),
      );
    } else {
      res = await ApiService.crearCliente(nuevoCliente);
    }

    setState(() => _isSaving = false);

    if (res['success'] == true && mounted) {
      final ClienteModel guardado = esEdicion
          ? nuevoCliente
          : (res['cliente'] is ClienteModel
              ? res['cliente'] as ClienteModel
              : nuevoCliente);
      Navigator.of(context).pop(guardado);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['error']?.toString() ?? 'Error al guardar cliente',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 550,
        height: 520,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(icon: Icon(Icons.search), text: 'Buscar RIF / Cédula'),
                Tab(
                  icon: Icon(Icons.person_add),
                  text: 'Registrar Cliente (SENIAT / Manual)',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text(
                          'Búsqueda por Nombre, Cédula o RIF',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchDocController,
                          decoration: InputDecoration(
                            labelText:
                                'Nombre / Cédula / RIF (búsqueda en tiempo real)',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.badge),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (_searchDocController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchDocController.clear();
                                          _onSearchChanged('');
                                        },
                                      )
                                    : null),
                          ),
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) => _buscarClienteLocal(),
                        ),
                        const SizedBox(height: 12),
                        if (_mostrandoRecientes)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Últimos clientes registrados',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        Expanded(
                          child: _resultados.isEmpty
                              ? Center(
                                  child: Text(
                                    _searchDocController.text.trim().isEmpty
                                        ? 'Aún no hay clientes registrados.'
                                        : 'Sin coincidencias. Use el registro SENIAT o Manual.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _resultados.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final c = _resultados[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        child: Text(
                                          c.nombreRazonSocial.isNotEmpty
                                              ? c.nombreRazonSocial[0]
                                                  .toUpperCase()
                                              : 'C',
                                        ),
                                      ),
                                      title: Text(
                                        c.nombreRazonSocial,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${c.tipoDocumento}-${c.numDocumento}'
                                        '${c.telefono != null && c.telefono!.isNotEmpty ? ' | Tel: ${c.telefono}' : ''}',
                                      ),
                                      onTap: () =>
                                          Navigator.of(context).pop(c),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context)
                                  .pop(ClienteModel.consumidorFinal()),
                          child: const Text('Usar Consumidor Final (ID 1)'),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'cedula',
                              label: Text('Cédula (Natural)'),
                              icon: Icon(Icons.person),
                            ),
                            ButtonSegment(
                              value: 'rif',
                              label: Text('RIF / Pasaporte'),
                              icon: Icon(Icons.business),
                            ),
                          ],
                          selected: {_grupoDoc},
                          onSelectionChanged: (seleccion) {
                            setState(() {
                              _grupoDoc = seleccion.first;
                              // El primer prefijo del grupo pasa a estar activo.
                              _tipoDoc = _prefijosPorGrupo[_grupoDoc]!.first;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            DropdownButton<String>(
                              value: _tipoDoc,
                              hint: Text(
                                _grupoDoc == 'cedula' ? 'V- / E-' : 'J- / G- / P-',
                              ),
                              items: _prefijosPorGrupo[_grupoDoc]!
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text('$t-'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _tipoDoc = val);
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _numDocController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Cédula / RIF (Sin Guiones)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isConsultingSeniat
                                  ? null
                                  : _consultarSeniat,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                              ),
                              icon: _isConsultingSeniat
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_download, size: 18),
                              label: const Text('SENIAT'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nombreController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre / Razón Social *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _direccionController,
                          decoration: const InputDecoration(
                            labelText: 'Dirección Fiscal',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _telefonoController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Teléfono',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Correo Electrónico',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _guardarYSeleccionar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: const Text('GUARDAR Y SELECCIONAR'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
