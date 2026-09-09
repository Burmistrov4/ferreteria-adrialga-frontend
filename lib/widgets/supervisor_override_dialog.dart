import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Diálogo de Autorización por PIN (Supervisor Override).
///
/// Se muestra ante acciones críticas (reversión de ventas, ajustes de
/// inventario) cuando el usuario activo es CAJERO. Devuelve el PIN capturado
/// via `Navigator.pop<String>` al confirmar, o `null` al cancelar.
/// Material 3 con `LayoutBuilder` + `SingleChildScrollView` para evitar
/// desbordamiento con el teclado activo (normativa AGENTS.md).
class SupervisorOverrideDialog extends StatefulWidget {
  final String titulo;
  final String descripcion;

  const SupervisorOverrideDialog({
    super.key,
    this.titulo = 'Autorización de Supervisor',
    this.descripcion =
        'Esta es una acción crítica. Ingrese el PIN de operación de un '
        'Supervisor o Administrador para continuar.',
  });

  @override
  State<SupervisorOverrideDialog> createState() =>
      _SupervisorOverrideDialogState();
}

class _SupervisorOverrideDialogState extends State<SupervisorOverrideDialog> {
  final _pinCtrl = TextEditingController();
  bool _ocultar = true;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty) Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth.isFinite && constraints.maxWidth < 400
              ? constraints.maxWidth
              : 400.0;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Container(
                width: ancho,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.admin_panel_settings,
                              color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.titulo,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.descripcion,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: _ocultar,
                      autofocus: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirmar(),
                      decoration: InputDecoration(
                        labelText: 'PIN de operación',
                        prefixIcon: const Icon(Icons.pin),
                        counterText: '',
                        suffixIcon: IconButton(
                          tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                          onPressed: () => setState(() => _ocultar = !_ocultar),
                          icon: Icon(
                            _ocultar ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                              ),
                              icon: const Icon(Icons.verified_user),
                              onPressed: _pinCtrl.text.trim().isEmpty
                                  ? null
                                  : _confirmar,
                              label: const Text('Autorizar'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}