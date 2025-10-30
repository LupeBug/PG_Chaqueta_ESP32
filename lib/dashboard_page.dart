// lib/dashboard_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // --- Batería ---
  final Battery _battery = Battery();
  int? batteryPct;
  Timer? _batteryTimer;

  @override
  void initState() {
    super.initState();
    _loadBattery();
    _batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadBattery());
  }

  Future<void> _loadBattery() async {
    try {
      final pct = await _battery.batteryLevel;
      if (mounted) setState(() => batteryPct = pct);
    } catch (_) {
      if (mounted) setState(() => batteryPct = 72);
    }
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ---------- Streams de Firestore ----------
  String? get _uidOrNull => FirebaseAuth.instance.currentUser?.uid;

  Stream<Map<String, dynamic>?> _lastRideStream() {
    final uid = _uidOrNull;
    if (uid == null) return const Stream.empty();
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rides')
        .orderBy('startAt', descending: true)
        .limit(1);
    return ref.snapshots().map((qs) => qs.docs.isEmpty ? null : qs.docs.first.data());
  }

  Stream<double> _monthKmStream() {
    final uid = _uidOrNull;
    if (uid == null) return const Stream.empty();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = (now.month == 12)
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rides')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('startAt', isLessThan: Timestamp.fromDate(nextMonth));

    return q.snapshots().map((qs) {
      double sum = 0.0;
      for (final d in qs.docs) {
        final km = (d.data()['distanceKm'] ?? 0) as num;
        sum += km.toDouble();
      }
      return sum;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final greeting = user?.email ?? 'ciclista';
    const double monthGoalKm = 150;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, $greeting 👋'),
        actions: [
          IconButton(
            tooltip: 'Conectividad',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.bluetooth),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadBattery,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // -------- Tarjetas de resumen --------
            Row(
              children: [
                // ----- Última salida -----
                Expanded(
                  child: StreamBuilder<Map<String, dynamic>?>(
                    stream: _lastRideStream(),
                    builder: (context, snap) {
                      final d = snap.data;
                      Widget child;
                      if (snap.connectionState == ConnectionState.waiting) {
                        child = const Text('Cargando última salida…');
                      } else if (d == null) {
                        child = const Text('Aún no tienes salidas.\nToca “Mapa” para empezar.');
                      } else {
                        final distanceKm = (d['distanceKm'] ?? 0) as num;
                        final durationSec = ((d['durationSec'] ?? 0) as num).toInt();
                        final startAt = (d['startAt'] is Timestamp)
                            ? (d['startAt'] as Timestamp).toDate()
                            : null;
                        final paceMinPerKm = (distanceKm > 0)
                            ? (durationSec / 60.0) / distanceKm.toDouble()
                            : 0.0;

                        child = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${distanceKm.toStringAsFixed(1)} km • ${_formatDuration(Duration(seconds: durationSec))}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ritmo ${paceMinPerKm.isFinite ? paceMinPerKm.toStringAsFixed(1) : '—'} min/km',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (startAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Fecha: ${startAt.day}/${startAt.month}/${startAt.year}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.pushNamed(context, '/rides'),
                                child: const Text('Ver detalles'),
                              ),
                            ),
                          ],
                        );
                      }

                      return _SummaryCard(
                        title: 'Última salida',
                        child: child,
                        onTap: () => Navigator.pushNamed(context, '/rides'),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // ----- Km del mes -----
                Expanded(
                  child: StreamBuilder<double>(
                    stream: _monthKmStream(),
                    builder: (context, snap) {
                      final double monthKm = (snap.data ?? 0.0).toDouble();
                      final double progress = monthGoalKm == 0
                          ? 0.0
                          : (monthKm / monthGoalKm).clamp(0.0, 1.0).toDouble();

                      return _SummaryCard(
                        title: 'Km del mes',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${monthKm.toStringAsFixed(1)} / ${monthGoalKm.toStringAsFixed(0)} km',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: LinearProgressIndicator(value: progress),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)} %',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.pushNamed(context, '/rides'),
                                child: const Text('Ver mes'),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.pushNamed(context, '/rides'),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // -------- Batería --------
            _SummaryCard(
              title: 'Batería',
              child: Row(
                children: [
                  const Icon(Icons.battery_full),
                  const SizedBox(width: 8),
                  Text(
                    batteryPct == null ? 'Leyendo…' : '$batteryPct %',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if ((batteryPct ?? 100) <= 20)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Batería baja'),
                    ),
                ],
              ),
              onTap: () => Navigator.pushNamed(context, '/safety'),
            ),
            const SizedBox(height: 16),

            // -------- Accesos rápidos --------
            Text('Accesos rápidos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _QuickAction(label: 'Mapa', icon: Icons.map, onTap: () => Navigator.pushNamed(context, '/map')),
                _QuickAction(label: 'Recorridos', icon: Icons.directions_bike, onTap: () => Navigator.pushNamed(context, '/rides')),
                _QuickAction(label: 'Checklist', icon: Icons.checklist_rtl, onTap: () => Navigator.pushNamed(context, '/safety')),
                _QuickAction(label: 'Consejos', icon: Icons.tips_and_updates, onTap: () => Navigator.pushNamed(context, '/tips')),
                _QuickAction(label: 'Conectividad', icon: Icons.bluetooth, onTap: () => Navigator.pushNamed(context, '/profile')),
              ],
            ),
            const SizedBox(height: 16),

            // -------- Consejo del día --------
            _SummaryCard(
              title: 'Consejo del día',
              child: const Text('Revisa la presión de tus neumáticos antes de salir. Mantén luces cargadas.'),
              onTap: () => Navigator.pushNamed(context, '/tips'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ---------- Widgets auxiliares ----------
class _SummaryCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onTap;
  const _SummaryCard({required this.title, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            offset: const Offset(0, 2),
            color: Colors.black.withOpacity(0.04),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: card);
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction({required this.label, required this.icon, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
