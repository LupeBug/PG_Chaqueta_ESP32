// lib/rides_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'ride_detail_page.dart';
import 'export_service.dart';

class RidesPage extends StatelessWidget {
  const RidesPage({super.key});

  Future<void> _onExport(BuildContext context, String kind) async {
    try {
      if (kind == 'csv') {
        final file = await ExportService.instance.exportCsvAndShare();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                file == null
                    ? 'No hay recorridos para exportar.'
                    : 'CSV generado y listo para compartir.',
              ),
            ),
          );
        }
      } else if (kind == 'pdf') {
        final file = await ExportService.instance.exportPdfAndShare();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                file == null
                    ? 'No hay recorridos para exportar.'
                    : 'PDF generado y listo para compartir.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Debes iniciar sesión')));
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rides')
        .orderBy('startAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Exportar',
            onSelected: (value) => _onExport(context, value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aún no tienes recorridos'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final id = docs[i].id;

              final status = (d['status'] ?? '') as String;
              final startAt = (d['startAt'] as Timestamp?)?.toDate();
              final endAt = (d['endAt'] as Timestamp?)?.toDate();
              final distanceKm = (d['distanceKm'] ?? 0.0) as num;
              final durationSec = (d['durationSec'] ?? 0) as int;
              final avgSpeedKmh = (d['avgSpeedKmh'] ?? 0.0) as num;
              final calories = (d['calories'] ?? 0) as int;

              String when = startAt != null
                  ? '${_two(startAt.day)}/${_two(startAt.month)}/${startAt.year} ${_two(startAt.hour)}:${_two(startAt.minute)}'
                  : 'Sin fecha';

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RideDetailPage(rideId: id, initialData: d),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Badge/ícono
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: status == 'completed'
                              ? Colors.green.withOpacity(0.12)
                              : Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          status == 'completed'
                              ? Icons.check
                              : Icons.directions_bike,
                          color: status == 'completed'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Datos
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              when,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${distanceKm.toStringAsFixed(2)} km  •  ${_fmtDuration(Duration(seconds: durationSec))}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Vel: ${avgSpeedKmh.toStringAsFixed(1)} km/h   Cal: $calories',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withOpacity(0.75),
                                  ),
                            ),
                            if (endAt != null)
                              Text(
                                'Fin: ${_two(endAt.day)}/${_two(endAt.month)}/${endAt.year} ${_two(endAt.hour)}:${_two(endAt.minute)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withOpacity(0.6),
                                    ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
