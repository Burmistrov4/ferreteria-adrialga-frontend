// lib/utils/parseo.dart
// Parseo numérico seguro para valores que llegan del backend.
// Prisma serializa los tipos Decimal como cadenas ("12.3400"); el cliente
// NUNCA debe castear directo: siempre double.tryParse con fallback 0.0
// (regla de manejo de datos del proyecto).
double numD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;