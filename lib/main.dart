// ============================================================
//  CONTROL DE INGRESO A EVENTOS
//  Lee el código de barras de la cédula colombiana (PDF417),
//  el QR de la cédula digital o un QR de prueba, busca el número
//  en una lista de Excel y controla dos pasos:
//    1. Confirmar  -> Pendiente  pasa a  Confirmado
//    2. Ingreso    -> Confirmado pasa a  Ingresó
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    const semilla = Color(0xFF1D4E89);
    return MaterialApp(
      title: 'Control de ingreso',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: semilla, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: semilla,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: const Inicio(),
    );
  }
}

// ------------------------------------------------------------
//  Utilidades de texto
// ------------------------------------------------------------
const pendiente = 'Pendiente';
const confirmado = 'Confirmado';
const ingreso = 'Ingresó';

String quitarTildes(String s) {
  const con = 'áéíóúüñÁÉÍÓÚÜÑ';
  const sin = 'aeiouunAEIOUUN';
  final r = StringBuffer();
  for (final ch in s.split('')) {
    final i = con.indexOf(ch);
    r.write(i >= 0 ? sin[i] : ch);
  }
  return r.toString();
}

/// "Número de Cédula" -> "numerodecedula" (para reconocer encabezados)
String normalizar(String s) =>
    quitarTildes(s).toLowerCase().replaceAll(RegExp(r'[\s_.\-º°#]'), '');

/// "0043840109" -> "43840109"
String soloNumero(String s) =>
    s.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

String horaActual() {
  final n = DateTime.now();
  String d(int x) => x.toString().padLeft(2, '0');
  return '${d(n.hour)}:${d(n.minute)}:${d(n.second)}';
}

final encabezadoCedula = RegExp(
    r'^(cedula|cc|documento|numerodedocumento|numerodocumento|identificacion|nodocumento)$');

// ------------------------------------------------------------
//  La lista de invitados (la "base de datos" en memoria)
// ------------------------------------------------------------
class Lista {
  String archivo;
  List<String> encabezados;
  List<List<String>> filas;
  int ced, nom, ape, est, hc, hi; // posición de cada columna

  Lista(this.archivo, this.encabezados, this.filas, this.ced, this.nom,
      this.ape, this.est, this.hc, this.hi);

  /// Recibe la tabla del Excel (filas y columnas) y busca los encabezados.
  factory Lista.desdeTabla(String archivo, List<List<String>> tabla) {
    int filaEnc = -1;
    for (int r = 0; r < tabla.length && r < 25; r++) {
      if (tabla[r].any((c) => encabezadoCedula.hasMatch(normalizar(c)))) {
        filaEnc = r;
        break;
      }
    }
    if (filaEnc < 0) {
      throw Exception('No se encontró una columna llamada "Cedula".');
    }
    final enc = tabla[filaEnc].map((e) => e.trim()).toList();
    int buscar(RegExp re) => enc.indexWhere((h) => re.hasMatch(normalizar(h)));

    final ced = buscar(encabezadoCedula);
    final nom = buscar(RegExp(r'^nombres?$|^nombrecompleto$'));
    final ape = buscar(RegExp(r'^apellidos?$'));
    int est = buscar(RegExp(r'^estado$'));
    int hc = buscar(RegExp(r'^horaconfirmacion$'));
    int hi = buscar(RegExp(r'^horaingreso$'));
    if (est < 0) { enc.add('Estado'); est = enc.length - 1; }
    if (hc < 0) { enc.add('Hora_confirmacion'); hc = enc.length - 1; }
    if (hi < 0) { enc.add('Hora_ingreso'); hi = enc.length - 1; }

    final filas = <List<String>>[];
    for (final original in tabla.skip(filaEnc + 1)) {
      if (ced >= original.length || soloNumero(original[ced]).isEmpty) continue;
      final f = List<String>.generate(
          enc.length, (i) => i < original.length ? original[i] : '');
      final e = normalizar(f[est]);
      f[est] = e.startsWith('ingres')
          ? ingreso
          : e.startsWith('confirm')
              ? confirmado
              : pendiente;
      filas.add(f);
    }
    if (filas.isEmpty) throw Exception('La columna Cédula no tiene datos.');
    return Lista(archivo, enc, filas, ced, nom, ape, est, hc, hi);
  }

  String nombre(List<String> f) {
    final t = [nom >= 0 ? f[nom] : '', ape >= 0 ? f[ape] : '']
        .join(' ')
        .trim();
    return t.isEmpty ? 'Invitado sin nombre' : t;
  }

  int contar(String estado) => filas.where((f) => f[est] == estado).length;

  /// Busca en la lista la cédula que viene dentro del texto leído.
  /// - QR de prueba: trae solo el número.
  /// - Cédula amarilla (PDF417): trae muchos datos; el número va con
  ///   ceros a la izquierda (10 dígitos) y después vienen los apellidos.
  (List<String>?, String) buscarCedula(String texto) {
    final limpio = texto.trim();
    if (RegExp(r'^\d+$').hasMatch(limpio)) {
      final n = soloNumero(limpio);
      for (final f in filas) {
        if (soloNumero(f[ced]) == n) return (f, n);
      }
    }
    final grupos =
        RegExp(r'\d{6,}').allMatches(texto).map((m) => m.group(0)!).toList();
    List<String>? mejor;
    for (final f in filas) {
      final id = soloNumero(f[ced]);
      if (id.isEmpty) continue;
      final conCeros = id.padLeft(10, '0');
      final coincide = grupos.any((g) =>
          g == id || g.endsWith(conCeros) || soloNumero(g) == id);
      if (coincide &&
          (mejor == null || id.length > soloNumero(mejor[ced]).length)) {
        mejor = f;
      }
    }
    if (mejor != null) return (mejor, soloNumero(mejor[ced]));

    // No está: mostrar el número que se alcanzó a leer
    String leido = soloNumero(limpio);
    if (texto.length >= 58 &&
        RegExp(r'^\d{10}$').hasMatch(texto.substring(48, 58))) {
      leido = soloNumero(texto.substring(48, 58));
    } else if (grupos.isNotEmpty) {
      grupos.sort((a, b) => a.length.compareTo(b.length));
      leido = soloNumero(grupos.first);
    }
    return (null, leido);
  }

  Map<String, dynamic> aJson() => {
        'archivo': archivo, 'encabezados': encabezados, 'filas': filas,
        'ced': ced, 'nom': nom, 'ape': ape, 'est': est, 'hc': hc, 'hi': hi,
      };

  factory Lista.deJson(Map<String, dynamic> j) => Lista(
        j['archivo'],
        List<String>.from(j['encabezados']),
        (j['filas'] as List).map((f) => List<String>.from(f)).toList(),
        j['ced'], j['nom'], j['ape'], j['est'], j['hc'], j['hi'],
      );
}

// Lista de ejemplo: las mismas 20 personas del Excel
const ejemplo = [
  ['43840109', 'María Fernanda', 'Gómez Restrepo'],
  ['1036598741', 'Juan Camilo', 'Pérez Ospina'],
  ['71589632', 'Carlos Alberto', 'Ramírez Zapata'],
  ['1017254896', 'Valentina', 'Muñoz Arango'],
  ['43567812', 'Luz Marina', 'Castaño Vélez'],
  ['1152698745', 'Santiago', 'Hernández Mejía'],
  ['98765432', 'Jorge Iván', 'Londoño Cardona'],
  ['1000458963', 'Isabella', 'Torres Quintero'],
  ['32456789', 'Gloria Patricia', 'Salazar Henao'],
  ['1128475963', 'Andrés Felipe', 'Rojas Giraldo'],
  ['43987654', 'Diana Carolina', 'Montoya Ríos'],
  ['1037612458', 'Sebastián', 'Álvarez Duque'],
  ['70123456', 'Luis Fernando', 'García Betancur'],
  ['1214723658', 'Mariana', 'Ochoa Correa'],
  ['15478963', 'Hernán Darío', 'Jaramillo Vargas'],
  ['1035874129', 'Laura Sofía', 'Marín Echeverri'],
  ['43125478', 'Adriana María', 'Osorio Bedoya'],
  ['1020478596', 'Daniel', 'Agudelo Sierra'],
  ['8356214', 'Óscar Eduardo', 'Valencia Toro'],
  ['1040758963', 'Camila Andrea', 'Ruiz Palacio'],
];

// ------------------------------------------------------------
//  Resultado que se muestra después de cada lectura
// ------------------------------------------------------------
enum Tipo { listo, ok, aviso, error }

class Resultado {
  final Tipo tipo;
  final String titulo, quien, detalle;
  final List<String>? filaParaAutorizar;
  const Resultado(this.tipo, this.titulo,
      {this.quien = '', this.detalle = '', this.filaParaAutorizar});
}

// ------------------------------------------------------------
//  Pantalla principal
// ------------------------------------------------------------
class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  static const claveGuardado = 'control_ingreso_v1';

  Lista? lista;
  bool cargando = true;
  String modo = 'confirmar';
  Resultado resultado = const Resultado(Tipo.listo, 'Listo para escanear',
      detalle: 'Paso actual: confirmar llegada.');

  final camara = MobileScannerController(
    formats: const [
      BarcodeFormat.pdf417, // cédula amarilla
      BarcodeFormat.qrCode, // cédula digital y QR de prueba
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );
  final manual = TextEditingController();
  bool pausado = false;
  String ultimoTexto = '';
  DateTime ultimaVez = DateTime(2000);

  @override
  void initState() {
    super.initState();
    recuperar();
  }

  @override
  void dispose() {
    camara.dispose();
    manual.dispose();
    super.dispose();
  }

  // ---------- Guardar el avance en el celular ----------
  Future<void> recuperar() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(claveGuardado);
    if (s != null) {
      try {
        lista = Lista.deJson(jsonDecode(s));
      } catch (_) {}
    }
    setState(() => cargando = false);
  }

  Future<void> guardar() async {
    final p = await SharedPreferences.getInstance();
    if (lista == null) {
      await p.remove(claveGuardado);
    } else {
      await p.setString(claveGuardado, jsonEncode(lista!.aJson()));
    }
  }

  void aviso(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ---------- Cargar el Excel ----------
  String textoCelda(xl.Data? c) {
    final v = c?.value;
    if (v == null) return '';
    if (v is xl.IntCellValue) return v.value.toString();
    if (v is xl.DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString();
  }

  Future<void> cargarExcel() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final bytes = r?.files.single.bytes;
    if (bytes == null) return;
    try {
      final libro = xl.Excel.decodeBytes(bytes);
      Object? ultimoError;
      for (final hoja in libro.tables.values) {
        final tabla =
            hoja.rows.map((f) => f.map(textoCelda).toList()).toList();
        try {
          setState(() => lista = Lista.desdeTabla(r!.files.single.name, tabla));
          await guardar();
          return;
        } catch (e) {
          ultimoError = e;
        }
      }
      throw ultimoError ?? Exception('El archivo está vacío.');
    } catch (e) {
      aviso('${e.toString().replaceFirst('Exception: ', '')} Revise el archivo.');
    }
  }

  void usarEjemplo() {
    final tabla = [
      ['Cedula', 'Nombres', 'Apellidos'],
      ...ejemplo.map((e) => List<String>.from(e)),
    ];
    setState(() => lista = Lista.desdeTabla('Lista de ejemplo', tabla));
    guardar();
  }

  // ---------- Lectura de la cámara ----------
  void alDetectar(BarcodeCapture captura) {
    if (pausado || lista == null) return;
    for (final b in captura.barcodes) {
      String? texto = b.rawValue ?? b.displayValue;
      if ((texto == null || texto.isEmpty) && b.rawBytes != null) {
        texto = String.fromCharCodes(b.rawBytes!);
      }
      if (texto == null || texto.isEmpty) continue;
      final ahora = DateTime.now();
      if (texto == ultimoTexto &&
          ahora.difference(ultimaVez).inSeconds < 5) return;
      ultimoTexto = texto;
      ultimaVez = ahora;
      pausado = true;
      procesar(texto);
      Future.delayed(const Duration(milliseconds: 2500), () => pausado = false);
      return;
    }
  }

  // ---------- Reglas de ingreso ----------
  void procesar(String texto) {
    final l = lista!;
    final (fila, numero) = l.buscarCedula(texto);
    Resultado r;
    if (fila == null) {
      r = Resultado(Tipo.error, 'No está en la lista',
          quien: numero.isEmpty ? 'Código no reconocido' : 'Cédula $numero',
          detalle: 'No puede ingresar.');
    } else {
      final nombre = l.nombre(fila);
      final estado = fila[l.est];
      if (modo == 'confirmar') {
        if (estado == pendiente) {
          fila[l.est] = confirmado;
          fila[l.hc] = horaActual();
          r = Resultado(Tipo.ok, 'Confirmado',
              quien: nombre,
              detalle: 'Cédula $numero. Ahora debe pasar al paso 2 (Ingreso).');
        } else if (estado == confirmado) {
          r = Resultado(Tipo.aviso, 'Ya estaba confirmado',
              quien: nombre,
              detalle: 'Confirmado a las ${fila[l.hc]}. Envíelo al ingreso.');
        } else {
          r = Resultado(Tipo.aviso, 'Ya ingresó',
              quien: nombre, detalle: 'Entró a las ${fila[l.hi]}.');
        }
      } else {
        if (estado == confirmado) {
          fila[l.est] = ingreso;
          fila[l.hi] = horaActual();
          r = Resultado(Tipo.ok, 'Puede ingresar',
              quien: nombre,
              detalle: 'Cédula $numero. Ingreso a las ${fila[l.hi]}.');
        } else if (estado == pendiente) {
          r = Resultado(Tipo.aviso, 'No ha confirmado',
              quien: nombre,
              detalle: 'Está en la lista pero no pasó por el paso 1.',
              filaParaAutorizar: fila);
        } else {
          r = Resultado(Tipo.error, 'Ya ingresó',
              quien: nombre,
              detalle:
                  'Entró a las ${fila[l.hi]}. No se permite un segundo ingreso.');
        }
      }
    }
    setState(() => resultado = r);
    guardar();
    avisar(r.tipo);
  }

  void dejarIngresar(List<String> fila) {
    final l = lista!;
    if (fila[l.hc].isEmpty) fila[l.hc] = horaActual();
    fila[l.est] = ingreso;
    fila[l.hi] = horaActual();
    setState(() => resultado = Resultado(Tipo.ok, 'Puede ingresar',
        quien: l.nombre(fila),
        detalle: 'Ingreso autorizado manualmente a las ${fila[l.hi]}.'));
    guardar();
  }

  /// Vibración y sonido para no tener que mirar la pantalla.
  void avisar(Tipo t) {
    if (t == Tipo.ok) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 180),
          () => HapticFeedback.heavyImpact());
      SystemSound.play(SystemSoundType.alert);
    }
  }

  // ---------- Compartir el Excel actualizado ----------
  // Crea el Excel en una carpeta temporal del celular y abre el menú
  // "Compartir" de Android para enviarlo por WhatsApp, correo, Drive...
  Future<void> compartirExcel() async {
    final l = lista!;
    try {
      final libro = xl.Excel.createExcel();
      final hoja = libro[libro.getDefaultSheet() ?? 'Sheet1'];
      hoja.appendRow(l.encabezados.map((h) => xl.TextCellValue(h)).toList());
      for (final f in l.filas) {
        hoja.appendRow(f.map((v) => xl.TextCellValue(v)).toList());
      }
      final bytes = libro.encode();
      if (bytes == null) throw Exception('No se pudo crear el Excel.');

      final hoy = DateTime.now().toIso8601String().substring(0, 10);
      final carpeta = await getTemporaryDirectory();
      final archivo = File('${carpeta.path}/ingreso_evento_$hoy.xlsx');
      await archivo.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(ShareParams(
        files: [
          XFile(archivo.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        ],
        text: 'Registro de ingreso al evento ($hoy)',
      ));
    } catch (e) {
      aviso('Error al crear el Excel: $e');
    }
  }

  Future<void> cambiarLista() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cambiar la lista?'),
        content: const Text(
            'Se borrarán los registros de este celular. Descargue antes el Excel actualizado si los necesita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cambiar lista')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => lista = null);
      guardar();
    }
  }

  // ---------- Pantallas ----------
  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return lista == null ? pantallaCargar() : pantallaEscaner();
  }

  Widget pantallaCargar() {
    return Scaffold(
      appBar: AppBar(title: const Text('Control de ingreso')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge_outlined, size: 72),
            const SizedBox(height: 16),
            Text('Lista de invitados',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
                'Cargue el archivo de Excel (.xlsx) con los invitados. Debe tener una columna llamada Cedula.',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: cargarExcel,
                icon: const Icon(Icons.upload_file),
                label: const Text('Cargar Excel')),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: usarEjemplo,
                child: const Text('Usar lista de ejemplo')),
          ],
        ),
      ),
    );
  }

  Widget pantallaEscaner() {
    final l = lista!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de ingreso'),
        actions: [
          IconButton(
            tooltip: 'Ver invitados',
            icon: const Icon(Icons.people_alt_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PantallaInvitados(lista: l))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) =>
                v == 'excel' ? compartirExcel() : cambiarLista(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'excel', child: Text('Compartir Excel con resultados')),
              PopupMenuItem(value: 'cambiar', child: Text('Cambiar lista')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'confirmar',
                  icon: Icon(Icons.how_to_reg),
                  label: Text('1. Confirmar')),
              ButtonSegment(
                  value: 'ingreso',
                  icon: Icon(Icons.door_front_door_outlined),
                  label: Text('2. Ingreso')),
            ],
            selected: {modo},
            onSelectionChanged: (s) => setState(() {
              modo = s.first;
              resultado = Resultado(Tipo.listo, 'Listo para escanear',
                  detalle: modo == 'confirmar'
                      ? 'Paso actual: confirmar llegada.'
                      : 'Paso actual: dejar ingresar.');
            }),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: camara, onDetect: alDetectar),
                  Center(
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Linterna',
                      icon: const Icon(Icons.flashlight_on_outlined),
                      onPressed: () => camara.toggleTorch(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ponga el código de barras de atrás de la cédula acostado dentro del recuadro, con buena luz y el celular quieto.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          tarjetaResultado(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: manual,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Escribir cédula a mano',
                      border: OutlineInputBorder()),
                  onSubmitted: (_) => buscarManual(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: buscarManual, child: const Text('Buscar')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              contador('Total', l.filas.length),
              contador('Pendientes', l.contar(pendiente)),
              contador('Confirmados', l.contar(confirmado)),
              contador('Ingresaron', l.contar(ingreso)),
            ],
          ),
        ],
      ),
    );
  }

  void buscarManual() {
    final v = manual.text.trim();
    if (v.isEmpty) return;
    procesar(v);
    manual.clear();
  }

  Widget contador(String t, int n) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text('$n',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(t, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );

  Widget tarjetaResultado() {
    final r = resultado;
    final esquema = Theme.of(context).colorScheme;
    final color = switch (r.tipo) {
      Tipo.ok => const Color(0xFF1E8E4E),
      Tipo.aviso => const Color(0xFFC98A00),
      Tipo.error => const Color(0xFFC62828),
      Tipo.listo => esquema.outline,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: r.tipo == Tipo.listo
            ? esquema.surfaceContainerHighest
            : color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.titulo,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: r.tipo == Tipo.listo ? null : color)),
          if (r.quien.isNotEmpty)
            Text(r.quien,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (r.detalle.isNotEmpty) Text(r.detalle),
          if (r.filaParaAutorizar != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => dejarIngresar(r.filaParaAutorizar!),
              child: const Text('Dejar ingresar de todas formas'),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  Pantalla con la lista de invitados
// ------------------------------------------------------------
class PantallaInvitados extends StatefulWidget {
  final Lista lista;
  const PantallaInvitados({super.key, required this.lista});
  @override
  State<PantallaInvitados> createState() => _PantallaInvitadosState();
}

class _PantallaInvitadosState extends State<PantallaInvitados> {
  String filtro = '';

  @override
  Widget build(BuildContext context) {
    final l = widget.lista;
    final q = normalizar(filtro);
    final visibles = l.filas
        .where((f) =>
            q.isEmpty ||
            normalizar(l.nombre(f)).contains(q) ||
            soloNumero(f[l.ced]).contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('Invitados (${l.filas.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar por nombre o cédula',
                  border: OutlineInputBorder()),
              onChanged: (v) => setState(() => filtro = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: visibles.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = visibles[i];
                final estado = f[l.est];
                final hora = f[l.hi].isNotEmpty
                    ? ' · entró ${f[l.hi]}'
                    : f[l.hc].isNotEmpty
                        ? ' · confirmó ${f[l.hc]}'
                        : '';
                return ListTile(
                  title: Text(l.nombre(f)),
                  subtitle: Text('CC ${soloNumero(f[l.ced])}$hora'),
                  trailing: Chip(
                    label: Text(estado),
                    backgroundColor: estado == ingreso
                        ? const Color(0xFF1E8E4E).withValues(alpha: 0.2)
                        : estado == confirmado
                            ? const Color(0xFFC98A00).withValues(alpha: 0.2)
                            : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
