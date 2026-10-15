// lib/utils/parseo.dart
// Parseo numérico seguro para valores que llegan del backend.
// Prisma serializa los tipos Decimal como cadenas ("12.3400"); el cliente
// NUNCA debe castear directo: siempre double.tryParse con fallback 0.0
// (regla de manejo de datos del proyecto).
double numD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

/// Entero seguro: acepta int, "42", "42.00" (Decimal de Prisma) e incluso
/// num con residuo decimal. Nunca lanza; devuelve [defecto] si no parsea.
int numI(dynamic v, {int defecto = 0}) {
  if (v == null) return defecto;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return defecto;
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? defecto;
}

/// Booleano seguro: el backend puede enviar true/false, 1/0, "1"/"0",
/// "true"/"false" o directamente null (tinyint de MySQL).
bool numB(dynamic v, {bool defecto = true}) {
  if (v == null) return defecto;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return defecto;
  if (s == 'true' || s == '1' || s == 'si' || s == 's' || s == 'y') return true;
  if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  return defecto;
}

/// Texto seguro: null/'' se normalizan a null para que los campos opcionales
/// (descripcion, email, telefono) no viajen como cadena vacia a la BD.
String? textoO(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Lista segura: el backend puede responder null o un Map inesperado donde el
/// cliente espera una lista. Devuelve siempre una lista tipada.
List<Map<String, dynamic>> listaDeMapas(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const <Map<String, dynamic>>[];
}