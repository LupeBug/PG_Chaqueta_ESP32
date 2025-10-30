import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SafetyWellnessPage extends StatefulWidget {
  const SafetyWellnessPage({super.key});

  @override
  State<SafetyWellnessPage> createState() => _SafetyWellnessPageState();
}

class _SafetyWellnessPageState extends State<SafetyWellnessPage> {
  late final String uid;
  late final DocumentReference<Map<String, dynamic>> docRef;

  final _pesoCtrl = TextEditingController();
  final _alturaCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness')
        .doc('safetyWellness');

    _ensureDefaults();
  }

  @override
  void dispose() {
    _pesoCtrl.dispose();
    _alturaCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _ensureDefaults() async {
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'checks': {
          'helmet': false,
          'lights': false,
          'brakes': false,
          'water': false,
          'tirePressure': false,
          'jacketBattery': false,
        },
        'weightKg': 0.0,
        'heightCm': 0.0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _setCheck(String key, bool value) {
    docRef.set({
      'checks': {key: value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _resetChecks() {
    docRef.set({
      'checks': {
        'helmet': false,
        'lights': false,
        'brakes': false,
        'water': false,
        'tirePressure': false,
        'jacketBattery': false,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _setPesoAltura({double? pesoKg, double? alturaCm}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (pesoKg != null) data['weightKg'] = pesoKg;
      if (alturaCm != null) data['heightCm'] = alturaCm;
      docRef.set(data, SetOptions(merge: true));
    });
  }

  static double _parseNum(String s) =>
      double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

  static double _calcBmi(double kg, double cm) {
    if (kg <= 0 || cm <= 0) return 0;
    final m = cm / 100.0;
    return kg / (m * m);
  }

  static String _bmiLabel(double bmi) {
    if (bmi <= 0) return '—';
    if (bmi < 18.5) return 'Bajo peso';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Sobrepeso';
    return 'Obesidad';
  }

  // ✅ NUEVA FUNCIÓN: Cerrar sesión y resetear checklist
  Future<void> _signOutAndResetChecklist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wellness')
          .doc('safetyWellness');

      await docRef.set({
        'checks': {
          'helmet': false,
          'lights': false,
          'brakes': false,
          'water': false,
          'tirePressure': false,
          'jacketBattery': false,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final d = snap.data!.data() ?? {};
        final checks = Map<String, dynamic>.from(d['checks'] ?? {});
        final weightKg = (d['weightKg'] ?? 0) as num;
        final heightCm = (d['heightCm'] ?? 0) as num;

        if (_pesoCtrl.text.isEmpty || _pesoCtrl.text != weightKg.toString()) {
          _pesoCtrl.text = weightKg == 0 ? '' : weightKg.toString();
        }
        if (_alturaCtrl.text.isEmpty || _alturaCtrl.text != heightCm.toString()) {
          _alturaCtrl.text = heightCm == 0 ? '' : heightCm.toString();
        }

        final bmi = _calcBmi(weightKg.toDouble(), heightCm.toDouble());
        final bmiLabel = _bmiLabel(bmi);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Seguridad y bienestar'),
            actions: [
              IconButton(
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout),
                onPressed: _signOutAndResetChecklist,
              ),
            ],
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _resetChecks,
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Reiniciar checklist'),
                  ),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Text(
                'Checklist pre-salida',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _switchTile(
                title: 'Casco',
                value: (checks['helmet'] ?? false) as bool,
                onChanged: (v) => _setCheck('helmet', v),
              ),
              _switchTile(
                title: 'Luces',
                value: (checks['lights'] ?? false) as bool,
                onChanged: (v) => _setCheck('lights', v),
              ),
              _switchTile(
                title: 'Frenos',
                value: (checks['brakes'] ?? false) as bool,
                onChanged: (v) => _setCheck('brakes', v),
              ),
              _switchTile(
                title: 'Agua',
                value: (checks['water'] ?? false) as bool,
                onChanged: (v) => _setCheck('water', v),
              ),
              _switchTile(
                title: 'Presión de llantas',
                value: (checks['tirePressure'] ?? false) as bool,
                onChanged: (v) => _setCheck('tirePressure', v),
              ),
              _switchTile(
                title: 'Batería de chaqueta',
                value: (checks['jacketBattery'] ?? false) as bool,
                onChanged: (v) => _setCheck('jacketBattery', v),
              ),
              const Divider(height: 28),

              Text('IMC', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),

              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      label: 'Peso (kg)',
                      controller: _pesoCtrl,
                      onChanged: (v) => _setPesoAltura(pesoKg: _parseNum(v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _numberField(
                      label: 'Altura (cm)',
                      controller: _alturaCtrl,
                      onChanged: (v) => _setPesoAltura(alturaCm: _parseNum(v)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Text(
                bmi > 0 ? 'IMC: ${bmi.toStringAsFixed(1)} - $bmiLabel' : 'IMC: —',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'El IMC es una estimación general.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 72),
            ],
          ),
        );
      },
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const UnderlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}
