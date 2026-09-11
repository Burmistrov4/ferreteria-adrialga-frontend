import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente_model.dart';
import '../services/api_service.dart';

/// Validador fiscal de Cédula/RIF: `^([VEJPG]-)?\d{7,9}$`.
/// Acepta prefijos V/E (cédula) y J/G/P (jurídico/pasaporte) y 7 a 9 dígitos.
/// Se aplica tras forzar mayúsculas y retirar guiones del input.
final RegExp _docFiscalRegExp = RegExp(r'^([VEJPG]-)?\d{7,9}$');

/// Normaliza un documento: mayúsculas, sin espacios ni guiones internos.
/// Si el usuario pega "v-1234567", devuelve "V1234567" (el prefijo visual
/// lo aporta el dropdown, así que aquí solo se depura el número).
String _normalizarDocumento(String valor) =>
    valor.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');

/// Mensaje de error de validación del documento o null si es válido.
String? _validarDocumento(String? valor, String tipoDoc) {
  final normalizado = _normalizarDocumento(valor ?? '');
  if (normalizado.isEmpty) return 'El número de documento es obligatorio';
  // Reconstruir con prefijo para validar contra el patrón fiscal completo.
  final conPrefijo = '$tipoDoc-$normalizado';
  if (!_docFiscalRegExp.hasMatch(conPrefijo)) {
    return 'Formato inválido: use 7 a 9 dígitos (ej. $tipoDoc-12345678)';
  }
  return null;
}

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

  // Clave de formulario para validación estricta del registro de cliente.
  final _formKey = GlobalKey<FormState>();

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
    final numDoc = _normalizarDocumento(_numDocController.text);
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
    // Validación estricta del formulario: documento fiscal con regex y
    // campos obligatorios antes de tocar la API.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nuevoCliente = ClienteModel(
      clienteId: widget.cliente?.clienteId,
      tipoDocumento: _tipoDoc,
      numDocumento: _normalizarDocumento(_numDocController.text),
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
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    // Diálogo elástico (equivalente a flexbox): en móvil/PC ocupa hasta el
    // 92% de la pantalla; en escritorio se limita a 560 px de ancho para que
    // no se estire deforme en monitores grandes. La altura nunca es fija:
    // el contenido fluye dentro de un rango con scroll interno garantizado.
    final dialogWidth = screenSize.width < 600 ? screenSize.width * 0.92 : 560.0;
    final dialogMaxHeight = screenSize.height * 0.90;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              // Contraste dinámico: en oscuro usa onSurfaceVariant, en claro
              // el gris de Material hereda del tema y se garantiza legible.
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.search), text: 'Buscar RIF / Cédula'),
                Tab(
                  icon: Icon(Icons.person_add),
                  text: 'Registrar Cliente (SENIAT / Manual)',
                ),
              ],
            ),
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBusquedaTab(colorScheme),
                  _buildRegistroTab(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusquedaTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              labelText: 'Nombre / Cédula / RIF (búsqueda en tiempo real)',
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
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Flexible(
            child: _resultados.isEmpty
                ? Center(
                    child: Text(
                      _searchDocController.text.trim().isEmpty
                          ? 'Aún no hay clientes registrados.'
                          : 'Sin coincidencias. Use el registro SENIAT o Manual.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _resultados.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = _resultados[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          child: Text(
                            c.nombreRazonSocial.isNotEmpty
                                ? c.nombreRazonSocial[0].toUpperCase()
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
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(ClienteModel.consumidorFinal()),
            child: const Text('Usar Consumidor Final (ID 1)'),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistroTab(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            // En pantallas angostas el bloque Documento apila verticalmente;
            // en anchas mantiene la fila compacta (flexbox adaptativo).
            LayoutBuilder(
              builder: (context, constraints) {
                final apilar = constraints.maxWidth < 420;
                final bloqueDocumento = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: apilar
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.start,
                  children: [
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
                          child: TextFormField(
                            controller: _numDocController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) => _validarDocumento(v, _tipoDoc),
                            decoration: const InputDecoration(
                              labelText: 'Cédula / RIF (Sin Guiones)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              helperText: '7 a 9 dígitos, sin guiones ni puntos',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isConsultingSeniat
                              ? null
                              : _consultarSeniat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                          ),
                          icon: _isConsultingSeniat
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_download, size: 18),
                          label: const Text('SENIAT'),
                        ),
                      ],
                    ),
                  ],
                );

                if (apilar) {
                  // Apilado: cada elemento ocupa su propia línea con zonas
                  // táctiles mínimas garantizadas.
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DropdownButton<String>(
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
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _numDocController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (v) => _validarDocumento(v, _tipoDoc),
                        decoration: const InputDecoration(
                          labelText: 'Cédula / RIF (Sin Guiones)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: '7 a 9 dígitos, sin guiones ni puntos',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isConsultingSeniat
                              ? null
                              : _consultarSeniat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                          ),
                          icon: _isConsultingSeniat
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_download, size: 18),
                          label: const Text('SENIAT'),
                        ),
                      ),
                    ],
                  );
                }
                return bloqueDocumento;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nombreController,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'El Nombre / Razón Social es obligatorio';
                }
                return null;
              },
              inputFormatters: [
                // Forzar mayúsculas en la Razón Social (fiscal).
                TextInputFormatter.withFunction((oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toUpperCase())),
              ],
              decoration: const InputDecoration(
                labelText: 'Nombre / Razón Social *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _direccionController,
              decoration: const InputDecoration(
                labelText: 'Dirección Fiscal',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final campos = [
                  Expanded(
                    child: TextFormField(
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
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ];
                // En pantallas angostas los dos campos apilan para evitar
                // Overflow/RenderFlex y garantizar 48dp táctiles.
                if (constraints.maxWidth < 420) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _telefonoController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo Electrónico',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  );
                }
                return Row(children: campos);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _guardarYSeleccionar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondary,
                  foregroundColor: colorScheme.onSecondary,
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
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
    );
  }
}
