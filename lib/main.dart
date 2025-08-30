import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
    runApp(const DbDKillerHelperApp());
}

/// 単一カウンタ（各サバイバー用）: 0→80秒のカウントアップ。
/// 60秒/80秒で通知、80秒到達で自動リセット→次タップで再スタート。
class SingleCounterTimer {
    final int maxSeconds;
    final List<int> notifyAt;

    bool running = false;
    int elapsed = 0; // 秒
    DateTime? _startedAt; // running=trueの開始時刻

    bool _notified60 = false;
    bool _notified80 = false;

    SingleCounterTimer({this.maxSeconds = 80, this.notifyAt = const [60, 80]});

    void startFromZero() {
        running = true;
        elapsed = 0;
        _startedAt = DateTime.now();
        _notified60 = false;
        _notified80 = false;
    }

    void stopAndReset() {
        running = false;
        elapsed = 0;
        _startedAt = null;
        _notified60 = false;
        _notified80 = false;
    }

    /// 定期的に呼ぶ。実時間から経過秒を再計算（Webでも正確）。
    void recompute({required VoidCallback onNotify60, required VoidCallback onNotify80}) {
        if (!running || _startedAt == null) return;
        final now = DateTime.now();
        elapsed = now.difference(_startedAt!).inSeconds;

        if (!_notified60 && notifyAt.contains(60) && elapsed >= 60 && elapsed < maxSeconds) {
            _notified60 = true;
            onNotify60();
        }
        if (!_notified80 && notifyAt.contains(80) && elapsed >= 80) {
            _notified80 = true;
            onNotify80();
            // 自動リセット
            stopAndReset();
        }
        if (elapsed > maxSeconds) {
            stopAndReset();
        }
    }
}

class PerkAsset {
    final String id;      // 'ds' | 'otr' | 'dh'
    final String label;   // 表示用（必要なら）
    final String path;    // 画像アセットのパス（ユーザーが設定）
    const PerkAsset(this.id, this.label, this.path);
}

class SurvivorState {
    final SingleCounterTimer timer = SingleCounterTimer();
    String selectedPerkId = 'ds';
    final Map<String, bool> desaturated = {'ds': false, 'otr': false, 'dh': false};
}

List<double> _saturationMatrix(double s) {
    final inv = 1 - s;
    final r = 0.2126 * inv;
    final g = 0.7152 * inv;
    final b = 0.0722 * inv;
    return <double>[
        r + s, g,     b,     0, 0,
        r,     g + s, b,     0, 0,
        r,     g,     b + s, 0, 0,
        0,     0,     0,     1, 0,
    ];
}

class DbDKillerHelperApp extends StatefulWidget {
    const DbDKillerHelperApp({super.key});
    @override
    State<DbDKillerHelperApp> createState() => _DbDKillerHelperAppState();
}

class _DbDKillerHelperAppState extends State<DbDKillerHelperApp> {
    // 画像パスはあなたが用意。pubspec.yaml の assets に登録してください。
    final List<PerkAsset> perkCatalog = const [
        PerkAsset('ds',  'Decisive Strike', 'assets/perks/ds.png'),
        PerkAsset('otr', 'Off The Record',  'assets/perks/otr.png'),
        PerkAsset('dh',  'Dead Hard',       'assets/perks/dh.png'),
    ];

    late final List<SurvivorState> survivors;
    Timer? ticker;

    @override
    void initState() {
        super.initState();
        survivors = List.generate(4, (_) => SurvivorState());
        // 全サバイバーのタイマーを定期再計算。
        ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
            for (final s in survivors) {
                s.timer.recompute(onNotify60: _notifyAt60, onNotify80: _notifyAt80);
            }
            if (mounted) setState(() {});
        });
    }

    @override
    void dispose() {
        ticker?.cancel();
        super.dispose();
    }

    void _notifyAt60() async {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
    }

    void _notifyAt80() async {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.click);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        SystemSound.play(SystemSoundType.click);
    }

    void _onPerkTap(SurvivorState s, String id) {
        setState(() {
            s.selectedPerkId = id;
            // ワンタップ：停止中→0から開始 / 実行中→停止して0へ
            if (!s.timer.running) {
                s.timer.startFromZero();
            } else {
                s.timer.stopAndReset();
            }
        });
    }

    void _onPerkLongPress(SurvivorState s, String id) {
        setState(() => s.desaturated[id] = !(s.desaturated[id] ?? false));
    }

    double _saturationFor(SurvivorState s, String id) {
        if (s.desaturated[id] == true) return 0.0;
        return id == s.selectedPerkId ? 1.0 : 0.35;
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
                    title: const Text('キラー用：サバイバー毎の単一タイマー'),
                    actions: [
                        IconButton(
                            tooltip: '全てリセット',
                            onPressed: () => setState(() {
                                for (final s in survivors) {
                                    s.timer.stopAndReset();
                                }
                            }),
                            icon: const Icon(Icons.restore),
                        ),
                    ],
                ),
                body: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: survivors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                        final s = survivors[i];
                        final progress = s.timer.running
                            ? (s.timer.elapsed.clamp(0, s.timer.maxSeconds) / s.timer.maxSeconds)
                            : 0.0;
                        final timeText = _fmt(s.timer.elapsed % (s.timer.maxSeconds + 1));
                        return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                        // 上部：円形プログレス＋時間表示
                                        Center(
                                            child: SizedBox(
                                                width: 180,
                                                height: 180,
                                                child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                        SizedBox(
                                                            width: 160,
                                                            height: 160,
                                                            child: CircularProgressIndicator(
                                                                value: progress,
                                                                strokeWidth: 10,
                                                            ),
                                                        ),
                                                        Text(
                                                            timeText,
                                                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                                                        ),
                                                        Positioned(
                                                            right: 0,
                                                            top: 0,
                                                            child: IconButton(
                                                                tooltip: 'このサバイバーをリセット',
                                                                icon: const Icon(Icons.stop_circle_outlined),
                                                                onPressed: () => setState(s.timer.stopAndReset),
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                            ),
                                        ),
                                        const SizedBox(height: 12),
                                        // 下部：3つのパーク画像（タップで開始/停止、長押しで彩度トグル）
                                        Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 16,
                                            runSpacing: 16,
                                            children: perkCatalog.map((p) {
                                                final sat = _saturationFor(s, p.id);
                                                final selected = p.id == s.selectedPerkId;
                                                return GestureDetector(
                                                    onTap: () => _onPerkTap(s, p.id),
                                                    onLongPress: () => _onPerkLongPress(s, p.id),
                                                    child: AnimatedContainer(
                                                        duration: const Duration(milliseconds: 120),
                                                        padding: const EdgeInsets.all(8),
                                                        decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(14),
                                                            border: Border.all(
                                                                color: selected
                                                                    ? Theme.of(context).colorScheme.primary
                                                                    : Theme.of(context).colorScheme.outlineVariant,
                                                                width: selected ? 2 : 1,
                                                            ),
                                                        ),
                                                        child: ColorFiltered(
                                                            colorFilter: ColorFilter.matrix(_saturationMatrix(sat)),
                                                            child: SizedBox(
                                                                width: 80,
                                                                height: 80,
                                                                child: Image.asset(
                                                                    p.path,
                                                                    fit: BoxFit.contain,
                                                                    errorBuilder: (ctx, err, st) => Container(
                                                                        alignment: Alignment.center,
                                                                        color: Colors.black12,
                                                                        child: const Text('Set image', style: TextStyle(fontSize: 12)),
                                                                    ),
                                                                ),
                                                            ),
                                                        ),
                                                    ),
                                                );
                                            }).toList(),
                                        ),
                                        const SizedBox(height: 6),
                                    ],
                                ),
                            ),
                        );
                    },
                ),
            ),
        );
    }
}

String _fmt(int secs) {
    final s = secs % 60;
    final m = secs ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
