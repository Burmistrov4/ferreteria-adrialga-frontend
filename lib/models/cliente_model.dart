import '../utils/parseo.dart';

class ClienteModel {
  final int? clienteId;
  final String rifCedula;
  final String nombreRazonSocial;
  final String? direccion;
  final String? telefono;
  final String? email;
  final String tipoDocumento;
  final String numDocumento;

  ClienteModel({
    this.clienteId,
    String? rifCedula,
    String? tipoDocumento,
    String? numDocumento,
    String? nombreRazonSocial,
    String? nombre,
    this.direccion,
    this.telefono,
    this.email,
  }) : tipoDocumento =
           tipoDocumento ??
           (rifCedula != null && rifCedula.contains('-')
               ? rifCedula.split('-').first
               : 'V'),
       numDocumento =
           numDocumento ??
           (rifCedula != null && rifCedula.contains('-')
               ? rifCedula.split('-').sublist(1).join('-')
               : (rifCedula ?? '')),
       rifCedula =
           rifCedula ??
           ((tipoDocumento != null && numDocumento != null)
               ? '$tipoDocumento-$numDocumento'
               : numDocumento ?? ''),
       nombreRazonSocial = nombreRazonSocial ?? nombre ?? '';

  int? get id => clienteId;
  String get nombre => nombreRazonSocial;

  factory ClienteModel.consumidorFinal() {
    return ClienteModel(
      clienteId: 1,
      tipoDocumento: 'V',
      numDocumento: '00000000',
      rifCedula: 'V-00000000',
      nombreRazonSocial: 'Consumidor Final',
    );
  }

  factory ClienteModel.fromJson(Map<String, dynamic> json) {
    final rif =
        (json['rifCedula'] ?? json['RIF_Cedula'] ?? json['numDocumento'] ?? '')
            .toString();
    String tipo = (json['tipoDocumento'] ?? '').toString();
    String num = (json['numDocumento'] ?? '').toString();

    if (tipo.isEmpty && rif.contains('-')) {
      final parts = rif.split('-');
      tipo = parts.first;
      num = parts.sublist(1).join('-');
    } else if (tipo.isEmpty) {
      tipo = 'V';
      num = rif;
    }

    // FASE 3: `clienteId` es `int?`. Si el backend manda "7" (string) el
    // casteo implicito a int? lanza TypeError. numI devuelve null cuando no
    // hay valor, preservando la semantica de "cliente sin persistir".
    final idCrudo = json['clienteId'] ?? json['Cliente_ID'] ?? json['id'];
    final int? idCliente = idCrudo == null ? null : numI(idCrudo);

    return ClienteModel(
      clienteId: idCliente,
      tipoDocumento: tipo,
      numDocumento: num,
      rifCedula: rif.isNotEmpty ? rif : '$tipo-$num',
      nombreRazonSocial:
          json['nombreRazonSocial'] ??
          json['Razon_Social'] ??
          json['nombre'] ??
          '',
      // '' -> null: no se persisten cadenas vacias en campos opcionales.
      direccion: textoO(json['direccion'] ?? json['Direccion']),
      telefono: textoO(json['telefono'] ?? json['Telefono']),
      email: textoO(json['email'] ?? json['Email']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (clienteId != null) 'Cliente_ID': clienteId,
      'RIF_Cedula': rifCedula,
      'Tipo_Documento': tipoDocumento,
      'Num_Documento': numDocumento,
      'Razon_Social': nombreRazonSocial,
      'Direccion': direccion,
      'Telefono': telefono,
      'Email': email,
    };
  }
}
