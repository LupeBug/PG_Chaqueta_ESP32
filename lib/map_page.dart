// lib/map_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

enum RideState { idle, recording, paused }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // --- Google Map ---
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final List<LatLng> _points = [];
  final Set<Marker> _markers = {};
  final CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(14.6349, -90.5069), // Fallback
    zoom: 14,
  );

  // Padding dinámico del mapa (según altura del bottom sheet)
  double _mapBottomPadding = 0;

  // --- Estado de sesión ---
  RideState _state = RideState.idle;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  StreamSubscription<Position>? _posSub;
  double _distanceMeters = 0.0;
  String? _rideDocId;

  // --- BLE y controles (listos para conectar más adelante) ---
  bool _lightOn = false;
  bool _leftOn = false;
  bool _rightOn = false;
  bool _hazardOn = false;
  String _bleStatus = 'Desconectado';

  // --- Preferencias/calorías (placeholder simple) ---
  double _weightKg = 70; // luego vendrá del Perfil
  static const double _metCycling = 8.0; // MET aprox. ciclismo moderado

  // --- Utils métricas ---
  double get _distanceKm => _distanceMeters / 1000.0;
  double get _avgSpeedKmh {
    final hours = _elapsed.inSeconds / 3600.0;
    if (hours <= 0) return 0;
    return _distanceKm / hours;
  }

  int get _calories {
    // kcal = MET * peso(kg) * horas
    final hours = _elapsed.inSeconds / 3600.0;
    return (hours * _metCycling * _weightKg).round();
  }

  @override
  void initState() {
    super.initState();
    _ensurePermissionAndLocate();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // ----------------------- Permisos y ubicación -----------------------
  Future<void> _ensurePermissionAndLocate() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled && mounted) {
      _showSnack('Activa tu GPS para usar el mapa.');
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) _showSnack('Permiso denegado permanentemente. Ve a Ajustes.');
      return;
    }
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition();
      _moveCamera(LatLng(pos.latitude, pos.longitude), zoom: 16);
    }
  }

  void _moveCamera(LatLng target, {double? zoom}) {
    final cam = CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: zoom ?? 16),
    );
    _mapController?.animateCamera(cam);
  }

  // ----------------------- Ticker tiempo -----------------------
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTicker() => _ticker?.cancel();

  // ----------------------- Checklist: validación previa -----------------------
  /// Lee el doc de checklist y verifica que todos los ítems estén en true.
  /// Retorna true si el checklist está completo.
  Future<bool> _isChecklistComplete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness')            // mismo path que en SafetyPage
        .doc('safetyWellness')
        .get();

    if (!doc.exists) return false;

    final data = doc.data() ?? {};
    final checks = Map<String, dynamic>.from(data['checks'] ?? {});

    const requiredKeys = [
      'helmet',
      'lights',
      'brakes',
      'water',
      'tirePressure',
      'jacketBattery',
    ];

    for (final k in requiredKeys) {
      final v = checks[k];
      if (v is! bool || v == false) return false;
    }
    return true;
  }

  /// Muestra un diálogo informando que falta completar checklist y ofrece ir a /safety.
  Future<void> _showChecklistDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checklist pendiente'),
        content: const Text(
          'Antes de iniciar una ruta, completa el checklist de seguridad y bienestar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamed(context, '/safety');
            },
            child: const Text('Ir al checklist'),
          ),
        ],
      ),
    );
  }

  // ----------------------- Grabación y Firestore -----------------------
  Future<void> _startRecording() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnack('Debes iniciar sesión.');
      return;
    }

    // ✅ Bloqueo: exige checklist completo antes de iniciar
    final ok = await _isChecklistComplete();
    if (!ok) {
      await _showChecklistDialog();
      return; // no iniciamos la grabación
    }

    final start = DateTime.now();
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rides')
        .add({
          'status': 'recording',
          'startAt': Timestamp.fromDate(start),
          'createdAt': FieldValue.serverTimestamp(),
        });

    setState(() {
      _rideDocId = docRef.id;
      _state = RideState.recording;
      _elapsed = Duration.zero;
      _distanceMeters = 0.0;
      _points.clear();
      _markers.clear();
    });

    // Punto de inicio
    final pos = await Geolocator.getCurrentPosition();
    final startLatLng = LatLng(pos.latitude, pos.longitude);
    _points.add(startLatLng);
    _markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: startLatLng,
        infoWindow: const InfoWindow(title: 'Inicio'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
    _drawPolyline();
    _moveCamera(startLatLng);
    _startTicker();
    _subscribePosition();
    _showSnack('Grabando recorrido...');
  }

  void _subscribePosition() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // 5 m para ahorrar batería
      ),
    ).listen((pos) {
      final p = LatLng(pos.latitude, pos.longitude);
      if (_points.isNotEmpty) {
        _distanceMeters += Geolocator.distanceBetween(
          _points.last.latitude,
          _points.last.longitude,
          p.latitude,
          p.longitude,
        );
      }
      _points.add(p);
      _drawPolyline();
      _moveCamera(p, zoom: 17);
      setState(() {});
    }, onError: (e) => _showSnack('Error de GPS: $e'));
  }

  void _pauseRecording() {
    if (_state != RideState.recording) return;
    _posSub?.pause();
    _stopTicker();
    setState(() => _state = RideState.paused);
    _showSnack('Sesión en pausa.');
  }

  void _resumeRecording() {
    if (_state != RideState.paused) return;
    _posSub?.resume();
    _startTicker();
    setState(() => _state = RideState.recording);
    _showSnack('Sesión reanudada.');
  }

  Future<void> _stopRecording() async {
    if (_state == RideState.idle) return;
    _posSub?.cancel();
    _stopTicker();

    if (_points.isNotEmpty) {
      _markers.removeWhere((m) => m.markerId.value == 'end');
      _markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _points.last,
          infoWindow: const InfoWindow(title: 'Fin'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('rides')
          .doc(_rideDocId)
          .update({
        'status': 'completed',
        'endAt': Timestamp.now(),
        'distanceKm': double.parse(_distanceKm.toStringAsFixed(3)),
        'durationSec': _elapsed.inSeconds,
        'avgSpeedKmh': double.parse(_avgSpeedKmh.toStringAsFixed(2)),
        'calories': _calories,
        'points': _points.map((p) => GeoPoint(p.latitude, p.longitude)).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showSnack('Recorrido guardado en Firebase.');
    } catch (e) {
      _showSnack('Error al guardar: $e');
    } finally {
      if (!mounted) return;
      setState(() => _state = RideState.idle);
    }
  }

  void _drawPolyline() {
    _polylines
      ..clear()
      ..add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _points,
          width: 5,
          color: Colors.blueAccent,
        ),
      );
    setState(() {});
  }

  // ----------------------- UI helpers -----------------------
  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _centerOnMe() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      _moveCamera(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      _showSnack('No se pudo obtener tu ubicación.');
    }
  }

  // ----------------------- BUILD -----------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa'),
        actions: [
          IconButton(
            tooltip: 'Centrar',
            onPressed: _centerOnMe,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          // MAPA con padding dinámico
          GoogleMap(
            initialCameraPosition: _initialCamera,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            markers: _markers,
            padding: EdgeInsets.only(bottom: _mapBottomPadding),
            onMapCreated: (c) => _mapController = c,
          ),

          // BOTTOM SHEET (PEEK/EXPANDIBLE) + listener para calcular padding
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              // n.extent = fracción de alto ocupada por el sheet (0..1)
              setState(() {
                _mapBottomPadding = n.extent * screenH;
              });
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.18, // peek
              minChildSize: 0.12,
              maxChildSize: 0.6,
              snap: true,
              snapSizes: const [0.18, 0.35, 0.6],
              builder: (context, scrollController) {
                final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    );

                return Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // FILA DE MÉTRICAS + BOTÓN MAESTRO
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                _MetricChip(label: 'Km', value: _distanceKm.toStringAsFixed(2)),
                                _MetricChip(label: 'Tiempo', value: _fmt(_elapsed)),
                                _MetricChip(label: 'Cal', value: '$_calories'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _PrimaryActionButton(
                            state: _state,
                            onStart: _startRecording,
                            onPause: _pauseRecording,
                            onResume: _resumeRecording,
                            onStop: _stopRecording,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Divider(color: cs.outlineVariant.withOpacity(0.6)),
                      const SizedBox(height: 8),

                      // Panel BLE en el sheet
                      Text('Controles', style: titleStyle),
                      const SizedBox(height: 10),
                      _BlePanel(
                        lightOn: _lightOn,
                        leftOn: _leftOn,
                        rightOn: _rightOn,
                        hazardOn: _hazardOn,
                        bleStatus: _bleStatus,
                        onToggleLight: () => setState(() => _lightOn = !_lightOn),
                        onToggleLeft: () => setState(() {
                          _leftOn = !_leftOn;
                          if (_leftOn) _rightOn = false;
                        }),
                        onToggleRight: () => setState(() {
                          _rightOn = !_rightOn;
                          if (_rightOn) _leftOn = false;
                        }),
                        onToggleHazard: () => setState(() {
                          _hazardOn = !_hazardOn;
                          if (_hazardOn) {
                            _leftOn = false;
                            _rightOn = false;
                          }
                        }),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ----------------------- Widgets de UI -----------------------

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          children: [
            const TextSpan(text: '', style: TextStyle()), // evita null style
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final RideState state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _PrimaryActionButton({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    String label;
    VoidCallback onPressed;

    switch (state) {
      case RideState.idle:
        icon = Icons.fiber_manual_record;
        label = 'Iniciar';
        onPressed = onStart;
        break;
      case RideState.recording:
        icon = Icons.pause;
        label = 'Pausar';
        onPressed = onPause;
        break;
      case RideState.paused:
        icon = Icons.play_arrow;
        label = 'Reanudar';
        onPressed = onResume;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
        ),
        const SizedBox(height: 8),
        // Botón detener independiente
        FilledButton.tonalIcon(
          onPressed: (state == RideState.recording || state == RideState.paused) ? onStop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Detener'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            backgroundColor: cs.errorContainer.withOpacity(0.4),
            foregroundColor: cs.onErrorContainer,
            disabledBackgroundColor: cs.surfaceVariant,
            disabledForegroundColor: cs.onSurface.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ],
    );
  }
}

class _BlePanel extends StatelessWidget {
  final bool lightOn, leftOn, rightOn, hazardOn;
  final String bleStatus;
  final VoidCallback onToggleLight, onToggleLeft, onToggleRight, onToggleHazard;

  const _BlePanel({
    required this.lightOn,
    required this.leftOn,
    required this.rightOn,
    required this.hazardOn,
    required this.bleStatus,
    required this.onToggleLight,
    required this.onToggleLeft,
    required this.onToggleRight,
    required this.onToggleHazard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget pill({
      required Widget child,
      required bool active,
      required VoidCallback onTap,
      EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      double radius = 28,
    }) {
      final bg = active ? cs.primary : cs.surface;
      final fg = active ? cs.onPrimary : cs.onSurface;
      final border = BorderSide(color: cs.outline.withOpacity(active ? 0 : 0.4));
      return Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: border),
        elevation: active ? 2 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleSmall!.copyWith(color: fg),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          // Luz
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              pill(
                active: lightOn,
                onTap: onToggleLight,
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline),
                    const SizedBox(width: 8),
                    Text('Luz ${lightOn ? "ON" : "OFF"}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Direccionales
          Row(
            children: [
              Expanded(
                child: pill(
                  active: leftOn,
                  onTap: onToggleLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  radius: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.turn_left),
                      const SizedBox(width: 8),
                      Text('Izquierda ${leftOn ? "ON" : "OFF"}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: pill(
                  active: rightOn,
                  onTap: onToggleRight,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  radius: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.turn_right),
                      const SizedBox(width: 8),
                      Text('Derecha ${rightOn ? "ON" : "OFF"}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Emergencia
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              pill(
                active: hazardOn,
                onTap: onToggleHazard,
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 8),
                    Text('Emergencia ${hazardOn ? "ON" : "OFF"}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'BLE: $bleStatus',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
