import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RideDetailPage extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? initialData;

  const RideDetailPage({super.key, required this.rideId, this.initialData});

  @override
  State<RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<RideDetailPage> {
  GoogleMapController? _mapController;

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  CameraPosition _initial = const CameraPosition(
    target: LatLng(14.6349, -90.5069),
    zoom: 12,
  );

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic>? data;

  bool _mapReady = false;
  List<LatLng> _routePoints = const [];

  @override
  void initState() {
    super.initState();
    data = widget.initialData;
    _listenRide();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // 🔹 NUEVA VERSIÓN: lectura por ruta directa (segura)
  void _listenRide() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rides')
        .doc(widget.rideId);

    _sub = ref.snapshots().listen(
      (doc) {
        if (doc.exists) {
          final d = doc.data()!;
          if (!mounted) return;
          setState(() => data = d);
          _renderMapFromData(d);
        } else if (data != null) {
          _renderMapFromData(data!);
        }
      },
      onError: (e) {
        print('Firestore error: $e');
        if (data != null) _renderMapFromData(data!);
      },
    );
  }

  // ----------------- Parseo y dibujo -----------------
  void _renderMapFromData(Map<String, dynamic> d) {
    final pts = _parsePoints(d['points']);
    setState(() {
      _routePoints = pts;
      _polylines = {
        Polyline(polylineId: const PolylineId('route'), points: pts, width: 5),
      };
      _markers = {};
      if (pts.isNotEmpty) {
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: pts.first,
            infoWindow: const InfoWindow(title: 'Inicio'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),
        );
        _markers.add(
          Marker(
            markerId: const MarkerId('end'),
            position: pts.last,
            infoWindow: const InfoWindow(title: 'Fin'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          ),
        );
      }
    });

    _centerRouteNow();
  }

  List<LatLng> _parsePoints(dynamic raw) {
    if (raw == null) return const [];
    final List<LatLng> out = [];
    if (raw is List) {
      for (final e in raw) {
        if (e is GeoPoint) {
          out.add(LatLng(e.latitude, e.longitude));
        } else if (e is Map) {
          final lat = (e['lat'] ?? e['latitude']);
          final lng = (e['lng'] ?? e['longitude']);
          if (lat is num && lng is num) {
            out.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        } else if (e is String) {
          final parsed = _parseLatLngFromString(e);
          if (parsed != null) out.add(parsed);
        }
      }
    }
    return out;
  }

  LatLng? _parseLatLngFromString(String s) {
    if (s.trim().isEmpty) return null;

    var t = s
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('°', '')
        .replaceAll('º', '')
        .trim();

    final commaIndex = t.indexOf(',');
    if (commaIndex == -1) return _parseLatLngWithRegex(t);

    final latPart = t.substring(0, commaIndex).trim();
    final lonPart = t.substring(commaIndex + 1).trim();

    final lat = _extractSigned(latPart, isLat: true);
    final lon = _extractSigned(lonPart, isLat: false);
    if (lat == null || lon == null) {
      return _parseLatLngWithRegex(t);
    }

    if (!_isLatLonValid(lat, lon)) return null;
    return LatLng(lat, lon);
  }

  double? _extractSigned(String part, {required bool isLat}) {
    final numMatch = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(part);
    if (numMatch == null) return null;

    var numStr = numMatch.group(0)!.replaceAll(',', '.');
    final value = double.tryParse(numStr);
    if (value == null) return null;

    final letter = RegExp(r'[NSEWnsew]').firstMatch(part)?.group(0)?.toUpperCase();
    double v = value;
    if (letter != null) {
      if (letter == 'S') v = -v;
      if (letter == 'W') v = -v;
    }

    if (isLat) {
      if (v < -90 || v > 90) return null;
    } else {
      if (v < -180 || v > 180) return null;
    }
    return v;
  }

  LatLng? _parseLatLngWithRegex(String t) {
    final r = RegExp(
      r'([-+]?\d+(?:[.,]\d+)?)\s*([NnSs])?.*?([-+]?\d+(?:[.,]\d+)?)\s*([EeWw])?',
    );

    final m = r.firstMatch(t);
    if (m == null) return null;

    String latNum = m.group(1)!.replaceAll(',', '.');
    String? latLet = m.group(2);
    String lonNum = m.group(3)!.replaceAll(',', '.');
    String? lonLet = m.group(4);

    double? lat = double.tryParse(latNum);
    double? lon = double.tryParse(lonNum);
    if (lat == null || lon == null) return null;

    if (latLet != null) lat = (latLet.toUpperCase() == 'S') ? -lat.abs() : lat.abs();
    if (lonLet != null) lon = (lonLet.toUpperCase() == 'W') ? -lon.abs() : lon.abs();

    if (!_isLatLonValid(lat, lon)) return null;
    return LatLng(lat, lon);
  }

  bool _isLatLonValid(double lat, double lon) {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  // --------------- Centrado robusto ---------------
  Future<void> _fitRouteToBounds() async {
    if (!_mapReady || _mapController == null) return;
    if (_routePoints.isEmpty) return;

    try {
      if (_routePoints.length == 1) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _routePoints.first, zoom: 16),
          ),
        );
        return;
      }

      final lats = _routePoints.map((e) => e.latitude);
      final lngs = _routePoints.map((e) => e.longitude);
      double minLat = lats.reduce((a, b) => a < b ? a : b);
      double maxLat = lats.reduce((a, b) => a > b ? a : b);
      double minLng = lngs.reduce((a, b) => a < b ? a : b);
      double maxLng = lngs.reduce((a, b) => a > b ? a : b);

      const eps = 0.0003;
      if ((maxLat - minLat).abs() < eps) {
        minLat -= eps;
        maxLat += eps;
      }
      if ((maxLng - minLng).abs() < eps) {
        minLng -= eps;
        maxLng += eps;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    } catch (_) {
      try {
        await Future.delayed(const Duration(milliseconds: 150));
        await _fitRouteToBounds();
      } catch (_) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _routePoints.last, zoom: 15),
          ),
        );
      }
    }
  }

  Future<void> _centerRouteNow() async {
    for (int i = 0; i < 5; i++) {
      if (!mounted) return;
      if (_mapReady && _mapController != null && _routePoints.isNotEmpty) {
        await _fitRouteToBounds();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  // ----------------------- UI -----------------------
  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del recorrido'),
        actions: [
          IconButton(
            tooltip: 'Centrar ruta',
            onPressed: _centerRouteNow,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _routePoints.isEmpty ? null : _centerRouteNow,
        icon: const Icon(Icons.my_location),
        label: const Text('Centrar ruta'),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SizedBox(
                  height: 320,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: _initial,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        polylines: _polylines,
                        markers: _markers,
                        onMapCreated: (c) async {
                          _mapController = c;
                          _mapReady = true;
                          await Future.delayed(const Duration(milliseconds: 60));
                          _centerRouteNow();
                        },
                      ),
                      if (_routePoints.isEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Sin puntos para mostrar',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _metrics(d),
                const SizedBox(height: 12),
                _notes(d),
              ],
            ),
    );
  }

  Widget _metrics(Map<String, dynamic> d) {
    final startAt = (d['startAt'] as Timestamp?)?.toDate();
    final endAt = (d['endAt'] as Timestamp?)?.toDate();
    final distanceKm = (d['distanceKm'] ?? 0) as num;
    final durationSec = ((d['durationSec'] ?? 0) as num).toInt();
    final avgSpeedKmh = (d['avgSpeedKmh'] ?? 0) as num;
    final calories = ((d['calories'] ?? 0) as num).toInt();

    String when = startAt != null
        ? '${_two(startAt.day)}/${_two(startAt.month)}/${startAt.year} '
          '${_two(startAt.hour)}:${_two(startAt.minute)}'
        : 'Sin fecha';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(when, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _kv('Distancia', '${distanceKm.toStringAsFixed(2)} km'),
                  _kv('Tiempo', _fmt(Duration(seconds: durationSec))),
                  _kv('Vel. media', '${avgSpeedKmh.toStringAsFixed(1)} km/h'),
                  _kv('Calorías', '$calories'),
                ],
              ),
              if (startAt != null && endAt != null) ...[
                const SizedBox(height: 6),
                Text('Inicio: $startAt'),
                Text('Fin:    $endAt'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _notes(Map<String, dynamic> d) {
    final notes = (d['notes'] is String) ? d['notes'] as String : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notas', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(notes.isEmpty ? 'Sin notas.' : notes),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
