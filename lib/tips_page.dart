import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  late final String uid;
  late final DocumentReference<Map<String, dynamic>> favRef;

  final TextEditingController _searchCtrl = TextEditingController();
  String _category = 'Todas';

  // ------ DATA: 50 tips ------
  final List<_Tip> _allTips = const [
    // Seguridad
    _Tip(id: 't01', text: 'Usa siempre casco, bien ajustado.', cat: 'Seguridad'),
    _Tip(id: 't02', text: 'Lleva luces delantera y trasera incluso de día.', cat: 'Seguridad'),
    _Tip(id: 't03', text: 'Ropa reflectante o colores vivos para ser visible.', cat: 'Seguridad'),
    _Tip(id: 't04', text: 'Señaliza con las manos antes de girar.', cat: 'Seguridad'),
    _Tip(id: 't05', text: 'Mantén distancia segura con vehículos y bordillos.', cat: 'Seguridad'),
    _Tip(id: 't06', text: 'Revisa frenos antes de salir.', cat: 'Seguridad'),
    _Tip(id: 't07', text: 'Evita audífonos en calle; usa un solo auricular si es imprescindible.', cat: 'Seguridad'),
    _Tip(id: 't08', text: 'Respeta las reglas de tránsito y semáforos.', cat: 'Seguridad'),
    _Tip(id: 't09', text: 'No pedalees por acera salvo que esté permitido.', cat: 'Seguridad'),
    _Tip(id: 't10', text: 'Considera espejos retrovisores en ciudad.', cat: 'Seguridad'),

    // Mantenimiento
    _Tip(id: 't11', text: 'Limpia y lubrica la cadena cada ~100 km o tras lluvia.', cat: 'Mantenimiento'),
    _Tip(id: 't12', text: 'Revisa presión de llantas antes de salir.', cat: 'Mantenimiento'),
    _Tip(id: 't13', text: 'Ajusta la altura del sillín (pierna casi extendida).', cat: 'Mantenimiento'),
    _Tip(id: 't14', text: 'Alinea manubrio y rueda delantera.', cat: 'Mantenimiento'),
    _Tip(id: 't15', text: 'Cambia pastillas/zapatas si frenan poco o hacen ruido.', cat: 'Mantenimiento'),
    _Tip(id: 't16', text: 'Ajusta cambios para evitar saltos de cadena.', cat: 'Mantenimiento'),
    _Tip(id: 't17', text: 'Revisa tensión de radios mensualmente.', cat: 'Mantenimiento'),
    _Tip(id: 't18', text: 'Guarda la bici en lugar seco.', cat: 'Mantenimiento'),
    _Tip(id: 't19', text: 'Lleva Allen, palancas, parches, bomba.', cat: 'Mantenimiento'),
    _Tip(id: 't20', text: 'Lleva una cámara de repuesto del tamaño correcto.', cat: 'Mantenimiento'),

    // Entrenamiento
    _Tip(id: 't21', text: 'Calienta al menos 10 minutos.', cat: 'Entrenamiento'),
    _Tip(id: 't22', text: 'Incrementa kilometraje gradualmente.', cat: 'Entrenamiento'),
    _Tip(id: 't23', text: 'Hidrátate cada 15–20 minutos.', cat: 'Entrenamiento'),
    _Tip(id: 't24', text: 'Come algo ligero antes de salir (plátano/avena).', cat: 'Entrenamiento'),
    _Tip(id: 't25', text: 'Estira al finalizar.', cat: 'Entrenamiento'),
    _Tip(id: 't26', text: 'Deja al menos 1 día de descanso tras sesiones duras.', cat: 'Entrenamiento'),
    _Tip(id: 't27', text: 'Escucha tu cuerpo: si hay dolor agudo, detente.', cat: 'Entrenamiento'),
    _Tip(id: 't28', text: 'Usa app o ciclocomputador para progreso.', cat: 'Entrenamiento'),
    _Tip(id: 't29', text: 'Cuida postura: espalda neutra, brazos relajados.', cat: 'Entrenamiento'),
    _Tip(id: 't30', text: 'Haz un ajuste de bicicleta (bike fit) si puedes.', cat: 'Entrenamiento'),

    // Planificación
    _Tip(id: 't31', text: 'Consulta el clima antes de salir.', cat: 'Planificación'),
    _Tip(id: 't32', text: 'Lleva rompevientos o impermeable si hay lluvia.', cat: 'Planificación'),
    _Tip(id: 't33', text: 'Evita rutas desconocidas sin mapa o compañía.', cat: 'Planificación'),
    _Tip(id: 't34', text: 'Informa tu ruta y hora de regreso a alguien.', cat: 'Planificación'),
    _Tip(id: 't35', text: 'Lleva identificación y contacto de emergencia.', cat: 'Planificación'),
    _Tip(id: 't36', text: 'Descarga el mapa para uso sin señal.', cat: 'Planificación'),
    _Tip(id: 't37', text: 'No ruedes de noche sin luces potentes.', cat: 'Planificación'),
    _Tip(id: 't38', text: 'Planea paradas de descanso e hidratación.', cat: 'Planificación'),
    _Tip(id: 't39', text: 'Evita horas pico de tráfico o calor extremo.', cat: 'Planificación'),
    _Tip(id: 't40', text: 'Asegura batería suficiente en el teléfono.', cat: 'Planificación'),

    // Bienestar
    _Tip(id: 't41', text: 'Usa protector solar (también con nubes).', cat: 'Bienestar'),
    _Tip(id: 't42', text: 'Dieta equilibrada con buena proteína y carbohidratos.', cat: 'Bienestar'),
    _Tip(id: 't43', text: 'Controla tu hidratación y descanso.', cat: 'Bienestar'),
    _Tip(id: 't44', text: 'Evita alcohol antes de pedalear.', cat: 'Bienestar'),
    _Tip(id: 't45', text: 'Ajusta la bici si sientes dolor lumbar/rodilla.', cat: 'Bienestar'),
    _Tip(id: 't46', text: 'Usa guantes para prevenir entumecimiento.', cat: 'Bienestar'),
    _Tip(id: 't47', text: 'Limpia casco y guantes con regularidad.', cat: 'Bienestar'),
    _Tip(id: 't48', text: 'Chequeos médicos periódicos si ruedas seguido.', cat: 'Bienestar'),
    _Tip(id: 't49', text: 'Duerme bien antes de rutas largas.', cat: 'Bienestar'),
    _Tip(id: 't50', text: 'Disfruta el camino y pedalea sin prisa.', cat: 'Bienestar'),
  ];

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tips')
        .doc('favorites');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Consejo del día determinístico usando la fecha
  _Tip get tipDelDia {
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    final rnd = Random(seed);
    return _allTips[rnd.nextInt(_allTips.length)];
  }

  List<_Tip> _filtered(List<_Tip> tips) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final cat = _category;
    return tips.where((t) {
      final byCat = (cat == 'Todas') ? true : t.cat == cat;
      final byTxt = q.isEmpty ? true : t.text.toLowerCase().contains(q);
      return byCat && byTxt;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ['Todas', ...{for (final t in _allTips) t.cat}];

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: favRef.snapshots(),
      builder: (context, snap) {
        final favIds = Set<String>.from((snap.data?.data()?['ids'] ?? []) as List? ?? []);
        final filtered = _filtered(_allTips);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Consejos para ciclistas'),
            actions: [
              IconButton(
                tooltip: 'Solo favoritos',
                onPressed: () => setState(() {
                  // toggle filtro "solo favoritos"
                  if (_category == 'Favoritos') {
                    _category = 'Todas';
                  } else {
                    _category = 'Favoritos';
                  }
                }),
                icon: Icon(_category == 'Favoritos' ? Icons.star : Icons.star_border),
              ),
            ],
          ),
          body: Column(
            children: [
              _TipDelDiaCard(tip: tipDelDia, isFav: favIds.contains(tipDelDia.id), onToggleFav: () => _toggleFav(favIds, tipDelDia.id)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Buscar consejo…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _category == 'Favoritos' ? 'Favoritos' : _category,
                      items: [
                        for (final c in cats) DropdownMenuItem(value: c, child: Text(c)),
                        const DropdownMenuItem(value: 'Favoritos', child: Text('Favoritos')),
                      ],
                      onChanged: (v) => setState(() => _category = v ?? 'Todas'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: (_category == 'Favoritos')
                      ? _filtered(_allTips.where((t) => favIds.contains(t.id)).toList()).length
                      : filtered.length,
                  itemBuilder: (context, i) {
                    final list = (_category == 'Favoritos')
                        ? _filtered(_allTips.where((t) => favIds.contains(t.id)).toList())
                        : filtered;
                    final tip = list[i];
                    final isFav = favIds.contains(tip.id);
                    return _TipTile(
                      tip: tip,
                      isFav: isFav,
                      onFav: () => _toggleFav(favIds, tip.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleFav(Set<String> current, String id) async {
    final newSet = Set<String>.from(current);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
    }
    await favRef.set({'ids': newSet.toList(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }
}

// ----------------- widgets auxiliares -----------------

class _TipDelDiaCard extends StatelessWidget {
  final _Tip tip;
  final bool isFav;
  final VoidCallback onToggleFav;
  const _TipDelDiaCard({required this.tip, required this.isFav, required this.onToggleFav});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tips_and_updates, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Consejo del día', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(tip.text),
                const SizedBox(height: 6),
                Text(tip.cat, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: isFav ? 'Quitar de favoritos' : 'Añadir a favoritos',
            onPressed: onToggleFav,
            icon: Icon(isFav ? Icons.star : Icons.star_border),
          )
        ],
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  final _Tip tip;
  final bool isFav;
  final VoidCallback onFav;

  const _TipTile({required this.tip, required this.isFav, required this.onFav});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.chevron_right),
        title: Text(tip.text),
        subtitle: Text(tip.cat),
        trailing: IconButton(
          tooltip: isFav ? 'Quitar de favoritos' : 'Añadir a favoritos',
          onPressed: onFav,
          icon: Icon(isFav ? Icons.star : Icons.star_border),
        ),
      ),
    );
  }
}

class _Tip {
  final String id;
  final String text;
  final String cat;
  const _Tip({required this.id, required this.text, required this.cat});
}
