/// Stub para plataformas sin selector web (móvil/desktop nativo).
/// Devuelve null: el formulario sigue aceptando una URL manual.
Future<({List<int> bytes, String mime})?> elegirImagen() async => null;
