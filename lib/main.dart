import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

void main() {
  runApp(const DbDKillerHelperApp());
}

/// --- Data Models ---
class PerkTimerDef {
  final String id;
  final String label;
  final int defaultSeconds; // editable via settings later
  const PerkTimerDef({required this.id, required this.label, required this.defaultSeconds});
}

class RunningTimer {
  final PerkTimerDef def;
  int remaining;
  bool isRunning;
  DateTime? lastTick; // for resume accuracy

  RunningTimer({required this.def})
      : remaining = def.defaultSeconds,
        isRunning = false,
        lastTick = null;

  void start() {
    if (remaining <= 0) remaining = def.defaultSeconds;
    isRunning = true;
    lastTick = DateTime.now();
  }

  void pause() {
    isRunning = false;
    lastTick = null;
  }

  void reset() {
    isRunning = false;
    remaining = def.defaultSeconds;
    lastTick = null;
  }

  void tick() {
    if (!isRunning || remaining <= 0) return;
    final now = DateTime.now();
    final dt = now.difference(lastTick ?? now).inMilliseconds;
    if (dt > 0) {
      remaining -= (dt / 1000).floor();
      if (remaining < 0) remaining = 0;
      lastTick = now;
    }
  }
}

class SurvivorState {
  String name;
  final List<TextEditingController> perkCtrls =
      List.generate(4, (_) => TextEditingController());
  final Map<String, RunningTimer> timers = {}; // key: def.id

  SurvivorState({required this.name});

  void dispose() {
    for (final c in perkCtrls) c.dispose();
  }
}

/// --- App State (in-widget for MVP) ---
class DbDKillerHelperApp extends StatefulWidget {
  const DbDKillerHelperApp({super.key});

  @override
  State<DbDKillerHelperApp> createState() => _DbDKillerHelperAppState();
}

class _DbDKillerHelperAppState extends State<DbDKillerHelperApp> {
  // Preset timers (editable later in a settings screen). Values are placeholders — adjust in-app.
  late List<PerkTimerDef> presetDefs;

  late final List<SurvivorState> survivors;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    survivors = [
      SurvivorState(name: 'Survivor 1'),
      SurvivorState(name: 'Survivor 2'),
      SurvivorState(name: 'Survivor 3'),
      SurvivorState(name: 'Survivor 4'),
    ];
    presetDefs = [
      PerkTimerDef(id: 'ds', label: '決死の一撃（DS）', defaultSeconds: 40),
      PerkTimerDef(id: 'endurance', label: '我慢（Endurance）', defaultSeconds: 10),
      PerkTimerDef(id: 'otr', label: 'オフレコ（OTR）', defaultSeconds: 80),
      PerkTimerDef(id: 'exhaust', label: '疲労（Exhaustion）', defaultSeconds: 40),
    ];
    ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      bool dirty = false;
      for (final s in survivors) {
        for (final t in s.timers.values) {
          final prev = t.remaining;
          t.tick();
          if (t.remaining != prev) dirty = true;
        }
      }
      if (dirty) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    for (final s in survivors) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DbD Killer Helper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('DbD キラー用サポート（手動タイマー）'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TimerPresetPage(presets: presetDefs),
                  ),
                );
                setState(() {});
              },
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: survivors.length,
          itemBuilder: (_, i) => SurvivorCard(
            survivor: survivors[i],
            presets: presetDefs,
            onChanged: () => setState(() {}),
          ),
        ),
      ),
    );
  }
}

/// --- UI Widgets ---
class SurvivorCard extends StatelessWidget {
  final SurvivorState survivor;
  final List<PerkTimerDef> presets;
  final VoidCallback onChanged;

  const SurvivorCard({super.key, required this.survivor, required this.presets, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: survivor.name,
                    decoration: const InputDecoration(
                      labelText: 'サバイバー名（任意）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => survivor.name = v,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '全タイマーをリセット',
                  onPressed: () {
                    for (final t in survivor.timers.values) {
                      t.reset();
                    }
                    onChanged();
                  },
                  icon: const Icon(Icons.restore),
                )
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(4, (i) => SizedBox(
                    width: 260,
                    child: TextField(
                      controller: survivor.perkCtrls[i],
                      decoration: InputDecoration(
                        labelText: 'パーク ${i + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: survivor.perkCtrls[i].text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  survivor.perkCtrls[i].clear();
                                  onChanged();
                                },
                              ),
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  )),
            ),
            const SizedBox(height: 12),
            Text('タイマープリセット', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((def) {
                final rt = survivor.timers[def.id] ??= RunningTimer(def: def);
                final isActive = rt.isRunning && rt.remaining > 0;
                return _TimerChip(rt: rt, onChanged: onChanged);
              }).toList(),
            ),
            if (survivor.timers.values.any((t) => t.remaining > 0)) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: survivor.timers.values
                    .where((t) => t.remaining > 0)
                    .map((t) => _ActiveTimerTile(rt: t, onChanged: onChanged))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  final RunningTimer rt;
  final VoidCallback onChanged;
  const _TimerChip({required this.rt, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isActive = rt.isRunning && rt.remaining > 0;
    return FilterChip(
      label: Text('${rt.def.label}\n${_fmt(rt.remaining)}'),
      selected: isActive,
      onSelected: (_) {
        if (!isActive) {
          rt.start();
        } else {
          rt.pause();
        }
        onChanged();
      },
      selectedColor: Theme.of(context).colorScheme.secondaryContainer,
      showCheckmark: false,
    );
  }
}

class _ActiveTimerTile extends StatelessWidget {
  final RunningTimer rt;
  final VoidCallback onChanged;
  const _ActiveTimerTile({required this.rt, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rt.def.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(_fmt(rt.remaining), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          IconButton(
            tooltip: rt.isRunning ? '一時停止' : '再開',
            icon: Icon(rt.isRunning ? Icons.pause_circle : Icons.play_circle),
            onPressed: () {
              rt.isRunning ? rt.pause() : rt.start();
              onChanged();
            },
          ),
          IconButton(
            tooltip: 'リセット',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () {
              rt.reset();
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class TimerPresetPage extends StatefulWidget {
  final List<PerkTimerDef> presets;
  const TimerPresetPage({super.key, required this.presets});

  @override
  State<TimerPresetPage> createState() => _TimerPresetPageState();
}

class _TimerPresetPageState extends State<TimerPresetPage> {
  late final List<_PresetEditRow> rows;

  @override
  void initState() {
    super.initState();
    rows = widget.presets
        .map((p) => _PresetEditRow(id: p.id, label: p.label, seconds: p.defaultSeconds))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('タイマープリセット（編集可能）')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('※ ここで表示している秒数は「仮の初期値」です。公式の最新仕様に合わせて各自で調整してください。'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (_, i) => _PresetRowEditor(row: rows[i]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                // In MVP, we only modify in-memory defaults (app restart will reset).
                // For production, persist with shared_preferences or local DB.
                for (final r in rows) {
                  final idx = widget.presets.indexWhere((p) => p.id == r.id);
                  if (idx >= 0) {
                    // ignore: invalid_use_of_visible_for_testing_member
                    widget.presets[idx] = PerkTimerDef(id: r.id, label: r.label, defaultSeconds: r.seconds);
                  }
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            )
          ],
        ),
      ),
    );
  }
}

class _PresetEditRow {
  final String id;
  String label;
  int seconds;
  _PresetEditRow({required this.id, required this.label, required this.seconds});
}

class _PresetRowEditor extends StatefulWidget {
  final _PresetEditRow row;
  const _PresetRowEditor({required this.row});

  @override
  State<_PresetRowEditor> createState() => _PresetRowEditorState();
}

class _PresetRowEditorState extends State<_PresetRowEditor> {
  late final TextEditingController labelCtrl;
  late final TextEditingController secCtrl;

  @override
  void initState() {
    super.initState();
    labelCtrl = TextEditingController(text: widget.row.label);
    secCtrl = TextEditingController(text: widget.row.seconds.toString());
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    secCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(labelText: 'ラベル', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => widget.row.label = v,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: secCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '秒数', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.row.seconds = int.tryParse(v) ?? widget.row.seconds,
              ),
            ),
            const SizedBox(width: 12),
            Text('id: ${widget.row.id}', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ],
    );
  }
}

String _fmt(int secs) {
  final s = secs % 60;
  final m = secs ~/ 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
