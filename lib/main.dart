import 'dart:async';
import 'package:flutter/material.dart';

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

/// Webでも確実に動くように、残り秒は「現在時刻と終了予定時刻の差」から毎秒再計算する。
class RunningTimer {
    final PerkTimerDef def;
    int remaining; // 秒
    bool isRunning;
    DateTime? endAt;

    RunningTimer({required this.def})
        : remaining = def.defaultSeconds,
          isRunning = false,
          endAt = null;

    void start() {
        if (remaining <= 0) remaining = def.defaultSeconds;
        endAt = DateTime.now().add(Duration(seconds: remaining));
        isRunning = true;
    }

    void pause() {
        if (!isRunning || endAt == null) return;
        final now = DateTime.now();
        remaining = endAt!.difference(now).inSeconds;
        if (remaining < 0) remaining = 0;
        endAt = null;
        isRunning = false;
    }

    void reset() {
        isRunning = false;
        endAt = null;
        remaining = def.defaultSeconds;
    }

    void recompute() {
        if (!isRunning || endAt == null) return;
        final now = DateTime.now();
        remaining = endAt!.difference(now).inSeconds;
        if (remaining <= 0) {
            remaining = 0;
            isRunning = false;
            endAt = null;
        }
    }
}

class SurvivorState {
    final Map<String, RunningTimer> timers = {}; // key: def.id

}

/// --- App ---
class DbDKillerHelperApp extends StatefulWidget {
    const DbDKillerHelperApp({super.key});

    @override
    State<DbDKillerHelperApp> createState() => _DbDKillerHelperAppState();
}

class _DbDKillerHelperAppState extends State<DbDKillerHelperApp> {
    late List<PerkTimerDef> presetDefs;
    late final List<SurvivorState> survivors;
    Timer? ticker;

    @override
    void initState() {
        super.initState();
        survivors = List.generate(4, (_) => SurvivorState());
        presetDefs = [
            PerkTimerDef(id: 'ds', label: '決死の一撃（DS）', defaultSeconds: 60),
            PerkTimerDef(id: 'otr', label: 'オフレコ（OTR）', defaultSeconds: 80),
        ];
        // 毎秒再計算（Webでもタブスロットリングの影響が小さい）
        ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            for (final s in survivors) {
                for (final t in s.timers.values) {
                    t.recompute();
                }
            }
            if (mounted) setState(() {});
        });
    }

    @override
    void dispose() {
        ticker?.cancel();
        // for (final s in survivors) {
        //     s.dispose();
        // }
        // super.dispose();
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
                                if (mounted) setState(() {});
                            },
                        ),
                    ],
                ),
                body: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: survivors.length,
                    itemBuilder: (_, i) => SurvivorCard(
                        index: i,
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
    final int index; // 表示用番号。サバイバー名の入力は廃止。
    final SurvivorState survivor;
    final List<PerkTimerDef> presets;
    final VoidCallback onChanged;

    const SurvivorCard({super.key, required this.index, required this.survivor, required this.presets, required this.onChanged});

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
                                const SizedBox.shrink(),
                                const Spacer(),
                                IconButton(
                                    tooltip: '全タイマーをリセット',
                                    onPressed: () {
                                        for (final t in survivor.timers.values) {
                                            t.reset();
                                        }
                                        onChanged();
                                    },
                                    icon: const Icon(Icons.restore),
                                ),
                            ],
                        ),

                        const SizedBox(height: 8),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: presets.map((def) {
                                final rt = survivor.timers[def.id] ??= RunningTimer(def: def);
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
                    Text(_fmt(rt.remaining)),
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
                        const Text('※ ここで表示している秒数は初期値です。公式の最新仕様に合わせて各自で調整してください。'),
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
                                for (final r in rows) {
                                    final idx = widget.presets.indexWhere((p) => p.id == r.id);
                                    if (idx >= 0) {
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
