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

/// 試合全体用のゲームタイマー（STARTで0からカウントアップ）
class GameTimer {
    bool running = false;
    int elapsed = 0; // 秒
    DateTime? _startedAt;

    void startFromZero() {
        running = true;
        elapsed = 0;
        _startedAt = DateTime.now();
    }

    void stopAndReset() {
        running = false;
        elapsed = 0;
        _startedAt = null;
    }

    void recompute() {
        if (!running || _startedAt == null) return;
        elapsed = DateTime.now().difference(_startedAt!).inSeconds;
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

    int hookCount = 0; // 0..3 の範囲
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
    final GameTimer gameTimer = GameTimer();
    Timer? ticker;

    @override
    void initState() {
        super.initState();
        survivors = List.generate(4, (_) => SurvivorState());
        // 全タイマーを定期再計算。
        ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
            for (final s in survivors) {
                s.timer.recompute(onNotify60: _notifyAt60, onNotify80: _notifyAt80);
            }
            gameTimer.recompute();
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

    // START ボタン：全サバイバー情報をリセットし、ゲームタイマーを0から開始
    void _onStartPressed() {
        setState(() {
            for (final s in survivors) {
                s.timer.stopAndReset();
                s.hookCount = 0;
                s.selectedPerkId = 'ds';
                s.desaturated.updateAll((_, __) => false);
            }
            gameTimer.startFromZero();
            HapticFeedback.lightImpact();
        });
    }

    // タイマー自体をタップして開始/停止。開始時に hookCount を自動で +1（最大3）。
    void _onTimerTap(SurvivorState s) {
        setState(() {
            if (!s.timer.running) {
                s.hookCount = (s.hookCount + 1).clamp(0, 3);
                s.timer.startFromZero();
            } else {
                s.timer.stopAndReset();
            }
        });
    }

    // 手動で釣り回数を増減
    void _incHook(SurvivorState s, int delta) {
        setState(() {
            s.hookCount = (s.hookCount + delta).clamp(0, 3);
        });
    }

    void _onPerkTap(SurvivorState s, String id) {
        // タイマーは開始しない。選択や彩度だけ扱う。
        setState(() {
            s.selectedPerkId = id;
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
                    titleSpacing: 8,
                    title: Row(
                        children: [
                            FilledButton(
                                onPressed: _onStartPressed,
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), minimumSize: const Size(0, 40)),
                                child: const Text('START', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.timer_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(
                                _fmt(gameTimer.elapsed),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                        ],
                    ),
                ),
                body: LayoutBuilder(
                    builder: (context, constraints) {
                        // 画面サイズから自動スケール計算（縦方向に確実に収まるように再設計）
                        const rows = 4;
                        const vSpacing = 6.0;           // 行間を少し詰める
                        const listPadV = 12.0;          // ListView 上下余白
                        const extraPerTile = 12.0;      // カード内の上下パディング総量の概算
                        final maxH = constraints.maxHeight;

                        // 実高さに近い見積もりで1行の高さを決める
                        final availableForTiles = maxH - listPadV * 2 - vSpacing * (rows - 1);
                        double tileH = (availableForTiles / rows) - (extraPerTile / rows);
                        tileH = tileH.clamp(64.0, 200.0);

                        // 行内の基準サイズ（右側が2段構成：パーク列＋釣りカウンタ）
                        const hookRowH = 24.0;          // 釣りカウンタ行の目標高さ
                        const betweenPerkAndHook = 4.0; // パークとカウンタの間
                        final perkSize = (tileH - hookRowH - betweenPerkAndHook).clamp(30.0, 70.0);
                        final timerSize = (tileH * 0.72).clamp(52.0, 112.0);
                        const gap = 8.0;

                        // 実コンテンツ高さを再計算して、スクロール可否を決める
                        final contentH = rows * (tileH + extraPerTile) + vSpacing * (rows - 1) + listPadV * 2;
                        final physics = contentH <= maxH
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics();

                        return ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: listPadV, horizontal: 8),
                            physics: physics,
                            itemCount: survivors.length,
                            separatorBuilder: (_, __) => const SizedBox(height: vSpacing),
                            itemBuilder: (_, i) => SizedBox(
                                height: tileH, // 1行の高さを固定して間延びを抑制
                                child: _SurvivorRow(
                                    state: survivors[i],
                                    perkCatalog: perkCatalog,
                                                                        tileHeight: tileH,
horizontalGap: gap,
                                ),
                            ),
                        );
                    },
                ),
            ),
        );
    }
}

class _SurvivorRow extends StatelessWidget {
    final SurvivorState state;
    final List<PerkAsset> perkCatalog;
    final double tileHeight;
    final double horizontalGap;

    const _SurvivorRow({
        required this.state,
        required this.perkCatalog,
        required this.tileHeight,
        required this.horizontalGap,
    });

    @override
    Widget build(BuildContext context) {
        return Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: LayoutBuilder(
                    builder: (context, box) {
                        // ---- 2-axis fit (width & height), ratio preserved ----
                        final availW = box.maxWidth;

                        // Make timer relatively smaller: increase perk/timer ratio a bit
                        const ratioPerkToTimer = 0.66; // was 0.58

                        // Vertical layout constants (match list builder assumptions)
                        const hookRowH = 24.0;
                        const betweenPerkAndHook = 4.0;

                        // Horizontal spacing estimates
                        const iconGap = 6.0;       // gap between perk icons (twice)
                        const perIconExtra = 10.0;
                        const trailingEdgeEpsilon = 2.0;// padding+border per perk container

                        // Base desired size from row height
                        final baseTimerByHeight = (tileHeight * 0.68).clamp(44.0, 112.0);

                        // Height limits: timer must fit tileHeight; perk must fit (tileHeight - hook - gap)
                        final maxPerkByHeight = (tileHeight - hookRowH - betweenPerkAndHook).clamp(24.0, tileHeight);
                        final heightLimitTimer = [tileHeight, maxPerkByHeight / ratioPerkToTimer].reduce((a, b) => a < b ? a : b);

                        // Width limit: timer + gap + 3 * (perk + extras) must fit availW
                        final widthLimitTimer = (availW - horizontalGap - 3 * (perIconExtra) - 2 * iconGap) / (1 + 3 * ratioPerkToTimer);

                        // Choose the minimum of base desire, width, and height constraints
                        double timerSize = baseTimerByHeight;
                        if (heightLimitTimer < timerSize) timerSize = heightLimitTimer;
                        if (widthLimitTimer < timerSize) timerSize = widthLimitTimer;
                        if (!(timerSize.isFinite) || timerSize <= 0) {
                            timerSize = 40.0; // fallback
                        }
                        // Enforce sensible bounds
                        timerSize = timerSize.clamp(36.0, 120.0);
                        final perkSize  = (timerSize * ratioPerkToTimer).clamp(24.0, 96.0);

                        // Rendering parameters
                        final progress = state.timer.running
                            ? (state.timer.elapsed.clamp(0, state.timer.maxSeconds) / state.timer.maxSeconds)
                            : 0.0;
                        final timeText = _fmt(state.timer.elapsed % (state.timer.maxSeconds + 1));
                        final stroke   = (timerSize * 0.09).clamp(4.0, 8.0);
                        final fontSize = (timerSize * 0.23).clamp(12.0, 24.0);

                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                                // 左：タイマー（タップで開始/停止）
                                SizedBox(
                                    width: timerSize,
                                    height: timerSize,
                                    child: GestureDetector(
                                        onTap: () => _contextOnTimerTap(context, state),
                                        child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                                CircularProgressIndicator(
                                                    value: progress,
                                                    strokeWidth: stroke,
                                                ),
                                                Text(
                                                    timeText,
                                                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
                                                ),
                                            ],
                                        ),
                                    ),
                                ),
                                SizedBox(width: horizontalGap),
                                // 右：パーク3つ（横一列）＋ 下に釣りカウンタ
                                Expanded(
                                    child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                            // 上段：パーク
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                    for (int idx = 0; idx < perkCatalog.length; idx++) ...[
                                                        _perkIcon(context, perkCatalog[idx], perkSize),
                                                        if (idx < perkCatalog.length - 1) const SizedBox(width: iconGap),
                                                    ],
                                                ],
                                            ),
                                            SizedBox(height: betweenPerkAndHook),
                                            // 下段：釣りカウンタ（中央寄せ）
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                    _miniIconButton(
                                                        context,
                                                        icon: Icons.remove,
                                                        onPressed: () => _contextIncHook(context, state, -1),
                                                        enabled: state.hookCount > 0,
                                                    ),
                                                    Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                            color: Theme.of(context).colorScheme.surfaceVariant,
                                                            borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text('${state.hookCount}/3', style: const TextStyle(fontWeight: FontWeight.w600)),
                                                    ),
                                                    _miniIconButton(
                                                        context,
                                                        icon: Icons.add,
                                                        onPressed: () => _contextIncHook(context, state, 1),
                                                        enabled: state.hookCount < 3,
                                                    ),
                                                ],
                                            ),
                                        ],
                                    ),
                                ),
                            ],
                        );
},
                ),
            ),
        );
    }

    Widget _perkIcon(BuildContext context, PerkAsset p, double perkSize) {
        final selected = p.id == state.selectedPerkId;
        final sat = _contextSaturation(context, state, p.id);
        return GestureDetector(
            onTap: () => _contextOnPerkTap(context, state, p.id),
            onLongPress: () => _contextOnPerkLongPress(context, state, p.id),
            child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                    ),
                ),
                child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(_saturationMatrix(sat)),
                    child: SizedBox(
                        width: perkSize,
                        height: perkSize,
                        child: Image.asset(
                            p.path,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, st) => Container(
                                alignment: Alignment.center,
                                color: Colors.black12,
                                child: const Text('Set image', style: TextStyle(fontSize: 10)),
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    Widget _miniIconButton(BuildContext context, {required IconData icon, required VoidCallback onPressed, bool enabled = true}) {
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IconButton(
                onPressed: enabled ? onPressed : null,
                icon: Icon(icon, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                style: IconButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
            ),
        );
    }

    // 親Stateの関数にアクセスする簡易ヘルパ
    double _contextSaturation(BuildContext ctx, SurvivorState s, String id) {
        final state = ctx.findAncestorStateOfType<_DbDKillerHelperAppState>();
        return state!._saturationFor(s, id);
    }

    void _contextOnPerkTap(BuildContext ctx, SurvivorState s, String id) {
        final state = ctx.findAncestorStateOfType<_DbDKillerHelperAppState>();
        state!._onPerkTap(s, id);
    }

    void _contextOnPerkLongPress(BuildContext ctx, SurvivorState s, String id) {
        final state = ctx.findAncestorStateOfType<_DbDKillerHelperAppState>();
        state!._onPerkLongPress(s, id);
    }

    void _contextOnTimerTap(BuildContext ctx, SurvivorState s) {
        final state = ctx.findAncestorStateOfType<_DbDKillerHelperAppState>();
        state!._onTimerTap(s);
    }

    void _contextIncHook(BuildContext ctx, SurvivorState s, int delta) {
        final state = ctx.findAncestorStateOfType<_DbDKillerHelperAppState>();
        state!._incHook(s, delta);
    }
}

String _fmt(int secs) {
    final s = secs % 60;
    final m = secs ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
