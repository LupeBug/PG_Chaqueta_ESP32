// lib/export_service.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

// PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportService {
  ExportService._();
  static final instance = ExportService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<List<Map<String, dynamic>>> _fetchRides() async {
    final uid = _uid;
    if (uid == null) return [];
    final qs = await _db
        .collection('users')
        .doc(uid)
        .collection('rides')
        .orderBy('startAt', descending: false)
        .get();
    return qs.docs.map((d) => d.data()).toList();
  }

  // ---------- CSV ----------
  Future<File?> exportCsvAndShare() async {
    final rides = await _fetchRides();
    if (rides.isEmpty) return null;

    final df = DateFormat('yyyy-MM-dd HH:mm');
    final rows = <List<dynamic>>[
      [
        'Fecha inicio',
        'Fecha fin',
        'Distancia (km)',
        'Duración (s)',
        'Vel media (km/h)',
        'Calorías',
        'Puntos (n)'
      ],
      ...rides.map((r) {
        final start = (r['startAt'] is Timestamp)
            ? (r['startAt'] as Timestamp).toDate()
            : null;
        final end = (r['endAt'] is Timestamp)
            ? (r['endAt'] as Timestamp).toDate()
            : null;
        return [
          start == null ? '' : df.format(start),
          end == null ? '' : df.format(end),
          (r['distanceKm'] ?? 0).toString(),
          (r['durationSec'] ?? 0).toString(),
          (r['avgSpeedKmh'] ?? 0).toString(),
          (r['calories'] ?? 0).toString(),
          (r['points'] is List) ? (r['points'] as List).length : 0,
        ];
      }),
    ];

    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/rides_export.csv');
    await file.writeAsString(csvData);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: 'rides_export.csv')],
      text: 'Exportación de recorridos',
    );
    return file;
  }

  // ---------- PDF ----------
  Future<File?> exportPdfAndShare() async {
    final rides = await _fetchRides();
    if (rides.isEmpty) return null;

    // Métricas
    final totalKm =
        rides.fold<num>(0, (s, r) => s + ((r['distanceKm'] ?? 0) as num));
    final totalCal =
        rides.fold<num>(0, (s, r) => s + ((r['calories'] ?? 0) as num));
    final totalSes = rides.length;

    // Serie distancia por día (últimos 30 días)
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 29));
    final buckets = <DateTime, double>{};
    for (int i = 0; i < 30; i++) {
      final d = DateTime(from.year, from.month, from.day + i);
      buckets[d] = 0;
    }
    for (final r in rides) {
      final ts = r['startAt'];
      if (ts is Timestamp) {
        final d = DateTime(ts.toDate().year, ts.toDate().month, ts.toDate().day);
        if (d.isAfter(from.subtract(const Duration(days: 1))) &&
            d.isBefore(now.add(const Duration(days: 1)))) {
          buckets[d] =
              (buckets[d] ?? 0) + ((r['distanceKm'] ?? 0) as num).toDouble();
        }
      }
    }
    final labels = buckets.keys.toList()..sort();
    final values = labels.map((d) => buckets[d] ?? 0).toList();
    final maxY =
        (values.isEmpty ? 0 : values.reduce(math.max)).clamp(0, 1e9).toDouble();

    final pdf = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm');

    // Portada
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Reporte de recorridos',
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generado: ${DateFormat('dd/MM/yyyy – HH:mm').format(DateTime.now())}',
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _metricBox('Sesiones', '$totalSes'),
                  _metricBox('Total km', totalKm.toStringAsFixed(1)),
                  _metricBox('Calorías', totalCal.toStringAsFixed(0)),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Distancia por día (últimos 30 días)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            _barChart(labels: labels, values: values, maxY: maxY),
          ],
        ),
      ),
    );

    // Tabla resumida
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final headers = ['Inicio', 'Fin', 'Km', 'Dur (s)', 'Vel (km/h)', 'Cal', 'Pts'];
          final dataRows = rides.map((r) {
            final start = (r['startAt'] is Timestamp)
                ? (r['startAt'] as Timestamp).toDate()
                : null;
            final end = (r['endAt'] is Timestamp)
                ? (r['endAt'] as Timestamp).toDate()
                : null;
            return [
              start == null ? '' : df.format(start),
              end == null ? '' : df.format(end),
              (r['distanceKm'] ?? 0).toString(),
              (r['durationSec'] ?? 0).toString(),
              (r['avgSpeedKmh'] ?? 0).toString(),
              (r['calories'] ?? 0).toString(),
              (r['points'] is List) ? (r['points'] as List).length.toString() : '0',
            ];
          }).toList();

          return pw.Table.fromTextArray(
            headers: headers,
            data: dataRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 10),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            headerHeight: 22,
            cellHeight: 18,
            border: null,
            headerAlignment: pw.Alignment.centerLeft,
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/rides_report.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: 'rides_report.pdf')],
      text: 'Reporte de recorridos',
    );
    return file;
  }

  // ---------- Helpers UI PDF ----------
  static pw.Widget _metricBox(String title, String value) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(color: PdfColors.grey700)),
      ],
    );
    }

  static pw.Widget _barChart({
    required List<DateTime> labels,
    required List<double> values,
    required double maxY,
    double height = 160,
  }) {
    if (labels.isEmpty || values.isEmpty) {
      return pw.Container(
        height: height,
        alignment: pw.Alignment.center,
        child: pw.Text('Sin datos para el periodo'),
      );
    }
    final safeMax = (maxY <= 0) ? 1.0 : maxY;
    final bars = <pw.Widget>[];
    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      final h = (v / safeMax) * (height - 20);
      final label = (i % 5 == 0) ? DateFormat('MM/dd').format(labels[i]) : '';

      bars.add(
        pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                height: h,
                width: 10,
                decoration: pw.BoxDecoration(
                  color: PdfColors.green600,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(label, style: const pw.TextStyle(fontSize: 6)),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: bars,
      ),
    );
  }
}
