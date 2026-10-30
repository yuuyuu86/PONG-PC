import 'dart:math' as math;

import 'catalog.dart';
import '../boxing/boxing.dart';
import 'common.dart';

/// 競技に依存しない試合進行: 開始前の操作説明 → プレー → 得点演出 → 終了。
/// 試合の状態は部屋を作ったPC（ホスト）だけが進め、相手には MatchState をそのまま送る。
enum MatchPhase { intro, play, point, over }

class LastPoint {
  const LastPoint({this.side, required this.reason, this.landX, required this.n});

  final int? side;
  final String reason;
  final double? landX;

  /// 何回目の得点か（演出の切り替え用）
  final int n;

  Map<String, Object?> toJson() => {'s': side, 'r': reason, 'x': landX == null ? null : r2(landX!), 'n': n};

  static LastPoint fromJson(Map<String, Object?> m) =>
      LastPoint(side: (m['s'] as num?)?.toInt(), reason: m['r'] as String, landX: (m['x'] as num?)?.toDouble(), n: (m['n'] as num).toInt());
}

class MatchState {
  MatchState({
    required this.game,
    required this.world,
    this.tick = 0,
    this.phase = MatchPhase.intro,
    this.timer = MatchEngine.introTime,
    List<int>? score,
    this.server,
    this.paused = false,
    this.resumeTimer = 0,
    this.lastPoint,
    this.winner,
    this.endReason,
    List<GameEvent>? events,
  })  : score = score ?? [0, 0],
        events = events ?? [];

  final GameKind game;
  GameWorld world;
  int tick;
  MatchPhase phase;
  double timer;
  List<int> score;
  int? server;
  bool paused;
  double resumeTimer;
  LastPoint? lastPoint;
  int? winner;
  String? endReason;

  /// このフレームで起きたこと（効果音・演出用）
  List<GameEvent> events;

  Map<String, Object?> toJson() => {
        'g': game.name,
        'k': tick,
        'p': phase.name,
        'tm': r2(timer),
        'sc': score,
        'sv': server,
        'ps': paused,
        'rs': r2(resumeTimer),
        'lp': lastPoint?.toJson(),
        'win': winner,
        'er': endReason,
        'w': world.toJson(),
        'ev': [for (final e in events) e.toJson()],
      };

  static MatchState fromJson(Map<String, Object?> m) {
    final game = GameKind.values.byName(m['g'] as String);
    return MatchState(
      game: game,
      world: game.rules.worldFromJson((m['w'] as Map).cast<String, Object?>()),
      tick: (m['k'] as num).toInt(),
      phase: MatchPhase.values.byName(m['p'] as String),
      timer: numD(m['tm']),
      score: [for (final v in m['sc'] as List) (v as num).toInt()],
      server: (m['sv'] as num?)?.toInt(),
      paused: m['ps'] == true,
      resumeTimer: numD(m['rs']),
      lastPoint: m['lp'] == null ? null : LastPoint.fromJson((m['lp'] as Map).cast<String, Object?>()),
      winner: (m['win'] as num?)?.toInt(),
      endReason: m['er'] as String?,
      events: [for (final e in m['ev'] as List) GameEvent.fromJson((e as Map).cast<String, Object?>())],
    );
  }
}

class MatchEngine {
  /// [rule] は部屋で選んだルール（何点先取か、ボクシングは試合時間の秒数）
  MatchEngine(this.game, {int? firstServer, math.Random? random, int? rule})
      : rules = game.rules,
        winScore = game == GameKind.boxing ? game.rules.winScore : (rule ?? game.rules.winScore),
        state = MatchState(game: game, world: game.rules.makeWorld()) {
    final w = state.world;
    if (rule != null && w is BoxingWorld) w.clock = rule.toDouble();
    final server = rules.serveRule == ServeRule.none ? null : (firstServer ?? (random ?? math.Random()).nextInt(2));
    state.server = server;
    rules.serve(state.world, server);
  }

  static const introTime = 4.0;
  static const pointTime = 1.5;
  static const resumeTime = 3.0;

  final GameKind game;
  final SportRules rules;
  final int? winScore;
  final MatchState state;

  void pause() {
    state.paused = true;
    state.resumeTimer = 0;
  }

  void resume() {
    if (!state.paused) return;
    state.paused = false;
    state.resumeTimer = resumeTime;
  }

  void step(List<PlayerInput> inputs, double dt) {
    final s = state;
    s.tick++;
    s.events = [];
    if (s.paused || s.phase == MatchPhase.over) return;
    if (s.resumeTimer > 0) {
      s.resumeTimer = math.max(0, s.resumeTimer - dt);
      return;
    }
    switch (s.phase) {
      case MatchPhase.intro:
        s.timer -= dt;
        if (s.timer <= 0) {
          s.phase = MatchPhase.play;
          s.events.add(const GameEvent('start'));
        }
        return;
      case MatchPhase.point:
        s.timer -= dt;
        if (s.timer <= 0) {
          rules.serve(s.world, s.server);
          s.phase = MatchPhase.play;
        }
        return;
      case MatchPhase.over:
        return;
      case MatchPhase.play:
        break;
    }

    final res = rules.step(s.world, inputs, dt, s.events, s.score);
    switch (res) {
      case null:
        return;
      case EndResult(:final winner, :final reason):
        _finish(winner, reason);
      case PointResult(:final side, :final reason, :final landX):
        if (side != null) s.score[side]++;
        s.lastPoint = LastPoint(side: side, reason: reason, landX: landX, n: (s.lastPoint?.n ?? 0) + 1);
        s.events.add(GameEvent('point', side: side));
        final win = winScore;
        if (side != null && win != null && s.score[side] >= win) {
          _finish(side, '$win点先取');
          return;
        }
        if (side != null) {
          switch (rules.serveRule) {
            case ServeRule.alternate:
              s.server = 1 - (s.server ?? 0);
            case ServeRule.winner:
              s.server = side;
            case ServeRule.none:
              break;
          }
        }
        s.phase = MatchPhase.point;
        s.timer = pointTime;
    }
  }

  void _finish(int winner, String reason) {
    state.phase = MatchPhase.over;
    state.winner = winner;
    state.endReason = reason;
    state.events.add(GameEvent('end', side: winner));
  }
}
