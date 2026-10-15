import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Gestión de Usuarios (Módulo de Configuración): CRUD protegido.
///
/// El usuario **raíz** (`admin` / Usuario_ID 1) es intocable: el backend
/// rechaza con 403 cualquier intento de desactivarlo o cambiarle rol/credencial.
/// "Borrar" es un **soft delete** (`Activo = false`) para preservar la
/// trazabilidad de las facturas históricas.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    SocketService.onDbUpdateModulo(_alDbUpdate);
  }

  void _alDbUpdate(String modulo) {
    if (!mounted || (modulo != 'usuarios' && modulo != '__reconexion__')) return;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final u = await ApiService.getUsuarios();
    if (!mounted) return;
    setState(() {
      _usuarios = u;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    SocketService.offDbUpdateModulo(_alDbUpdate);
    super.dispose();
  }

  bool _esRoot(Map<String, dynamic> u) =>
      u['Usuario_ID'] == 1 ||
      (u['Credencial'] ?? '').toString().toLowerCase() == 'admin';

  void _msg(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? usuario}) async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UsuarioForm(usuario: usuario),
    );
    if (datos == null) return;
    final r = usuario == null
        ? await ApiService.crearUsuario(datos)
        : await ApiService.actualizarUsuario(
            usuario['Usuario_ID'] as int, datos);
    if (r['success'] == true) {
      _msg(usuario == null ? 'Usuario creado' : 'Usuario actualizado');
      await _cargar();
    } else {
      _msg(r['error']?.toString() ?? 'No se pudo guardar', error: true);
    }
  }

  Future<void> _desactivar(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar usuario'),
        content: Text(
            '¿Desactivar a "${u['Nombre']}"? No se borra: se marca inactivo '
            'para conservar la trazabilidad de sus facturas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ApiService.desactivarUsuario(u['Usuario_ID'] as int);
    if (r['success'] == true) {
      _msg('Usuario desactivado');
      await _cargar();
    } else {
      _msg(r['error']?.toString() ?? 'No se pudo desactivar', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          IconButton(
              onPressed: _cargar, icon: const Icon(Icons.refresh), tooltip: 'Recargar'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _usuarios.length,
                itemBuilder: (context, i) {
                  final u = _usuarios[i];
                  final root = _esRoot(u);
                  final activo = u['Activo'] == true;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            activo ? cs.primaryContainer : cs.surfaceContainerHighest,
                        child: Icon(root ? Icons.shield : Icons.person,
                            color: activo
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(u['Nombre']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (root) ...[
                            const SizedBox(width: 6),
                            Chip(
                              label: const Text('ROOT',
                                  style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: cs.errorContainer,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                          '${u['Credencial']} · ${u['Rol']}${activo ? '' : ' · INACTIVO'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar',
                            onPressed: () => _abrirFormulario(usuario: u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.person_off),
                            tooltip: root
                                ? 'El root no puede desactivarse'
                                : 'Desactivar',
                            onPressed: (root || !activo) ? null : () => _desactivar(u),
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

/// Formulario modal Crear/Editar usuario.
class _UsuarioForm extends StatefulWidget {
  final Map<String, dynamic>? usuario;
  const _UsuarioForm({this.usuario});

  @override
  State<_UsuarioForm> createState() => _UsuarioFormState();
}

class _UsuarioFormState extends State<_UsuarioForm> {
  late final TextEditingController _nombre;
  late final TextEditingController _credencial;
  final _pass = TextEditingController();
  final _pin = TextEditingController();
  String _rol = 'CAJERO';
  bool _activo = true;

  bool get _esEdicion => widget.usuario != null;

  bool get _esRoot {
    final u = widget.usuario;
    if (u == null) return false;
    return u['Usuario_ID'] == 1 ||
        (u['Credencial'] ?? '').toString().toLowerCase() == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _nombre =
        TextEditingController(text: widget.usuario?['Nombre']?.toString() ?? '');
    _credencial = TextEditingController(
        text: widget.usuario?['Credencial']?.toString() ?? '');
    _rol = widget.usuario?['Rol']?.toString() ?? 'CAJERO';
    _activo = widget.usuario == null || widget.usuario?['Activo'] == true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _credencial.dispose();
    _pass.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _enviar() {
    final nombre = _nombre.text.trim();
    final cred = _credencial.text.trim();
    if (nombre.isEmpty || cred.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre y credencial son obligatorios')),
      );
      return;
    }
    if (!_esEdicion && _pass.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('La contraseña debe tener al menos 4 caracteres')),
      );
      return;
    }
    final data = <String, dynamic>{
      'Nombre': nombre,
      'Rol': _rol,
      'Activo': _activo,
    };
    if (!_esRoot) data['Credencial'] = cred;
    if (_pass.text.trim().isNotEmpty) data['Password'] = _pass.text.trim();
    if (_pin.text.trim().isNotEmpty) data['PinOperaciones'] = _pin.text.trim();
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar usuario' : 'Nuevo usuario'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _credencial,
              enabled: !_esRoot,
              decoration: InputDecoration(
                labelText: 'Credencial / Usuario',
                helperText: _esRoot
                    ? 'La credencial del root no puede cambiarse'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                helperText: _esEdicion
                    ? 'Dejar vacío para no cambiarla'
                    : 'Mínimo 4 caracteres',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _rol,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'CAJERO', child: Text('Cajero')),
                DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                DropdownMenuItem(value: 'ADMIN', child: Text('Administrador')),
              ],
              onChanged:
                  _esRoot ? null : (v) => setState(() => _rol = v ?? 'CAJERO'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN de operaciones (opcional)',
                helperText: 'Para autorizar acciones críticas (Supervisor/Admin)',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _activo,
              onChanged: _esRoot ? null : (v) => setState(() => _activo = v),
              title: const Text('Activo'),
              subtitle:
                  _esRoot ? const Text('El root no puede desactivarse') : null,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _enviar, child: const Text('Guardar')),
      ],
    );
  }
}
