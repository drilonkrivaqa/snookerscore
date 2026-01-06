import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const SnookerScoreApp());

class SnookerScoreApp extends StatelessWidget {
  const SnookerScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snooker Score Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const HomePage(),
    );
  }
}

enum Player { a, b }

extension PlayerX on Player {
  String get label => this == Player.a ? "Player 1" : "Player 2";
  Player get other => this == Player.a ? Player.b : Player.a;
}

enum Ball { red, yellow, green, brown, blue, pink, black }

extension BallX on Ball {
  String get name {
    switch (this) {
      case Ball.red:
        return "Red";
      case Ball.yellow:
        return "Yellow";
      case Ball.green:
        return "Green";
      case Ball.brown:
        return "Brown";
      case Ball.blue:
        return "Blue";
      case Ball.pink:
        return "Pink";
      case Ball.black:
        return "Black";
    }
  }

  int get points {
    switch (this) {
      case Ball.red:
        return 1;
      case Ball.yellow:
        return 2;
      case Ball.green:
        return 3;
      case Ball.brown:
        return 4;
      case Ball.blue:
        return 5;
      case Ball.pink:
        return 6;
      case Ball.black:
        return 7;
    }
  }

  Color get color {
    switch (this) {
      case Ball.red:
        return Colors.red;
      case Ball.yellow:
        return Colors.yellow.shade700;
      case Ball.green:
        return Colors.green.shade700;
      case Ball.brown:
        return Colors.brown;
      case Ball.blue:
        return Colors.blue.shade700;
      case Ball.pink:
        return Colors.pink.shade300;
      case Ball.black:
        return Colors.black;
    }
  }
}

/// A minimal “frame state” engine.
/// This is v1 and intentionally practical:
/// - Treats reds as remaining count
/// - During reds phase: legal sequence is Red -> Color -> Red -> Color ...
/// - Once reds are 0 and you are “on a color”, we move into colors clearance phase:
///   Yellow -> Green -> Brown -> Blue -> Pink -> Black (in order).
/// - Free ball: counts as 1 and then player must take a color.
/// - Fouls: points go to opponent, do not change turn automatically here (user decides with Switch Turn button).
class FrameState {
  int scoreA = 0;
  int scoreB = 0;

  Player turn = Player.a;

  int redsRemaining = 15;
  bool inColorsClearance = false; // true once redsRemaining == 0 and a color has been nominated in order
  Ball nextColorInClearance = Ball.yellow;

  // expectation helper
  bool expectingRed = true; // at start: red
  bool freeBallActive = false; // if true, next “pot” should be treated as free ball

  // breaks
  int currentBreak = 0;
  int highBreakA = 0;
  int highBreakB = 0;

  // logging for undo
  final List<_Action> _history = [];

  int get scoreTurn => turn == Player.a ? scoreA : scoreB;
  int get scoreOpp => turn == Player.a ? scoreB : scoreA;

  void _setScoreTurn(int v) {
    if (turn == Player.a) {
      scoreA = v;
    } else {
      scoreB = v;
    }
  }

  void _setScoreOpp(int v) {
    if (turn == Player.a) {
      scoreB = v;
    } else {
      scoreA = v;
    }
  }

  void _updateHighBreak() {
    if (turn == Player.a) {
      if (currentBreak > highBreakA) highBreakA = currentBreak;
    } else {
      if (currentBreak > highBreakB) highBreakB = currentBreak;
    }
  }

  String get expectedText {
    if (freeBallActive) return "Expected: Free ball (counts as 1), then a color";
    if (inColorsClearance) return "Expected: ${nextColorInClearance.name} (colors in order)";
    return expectingRed ? "Expected: Red" : "Expected: Color";
  }

  int suggestedFoulPoints({Ball? ballOn, Ball? ballInvolved}) {
    final candidates = [4];
    if (ballOn != null) candidates.add(ballOn.points);
    if (ballInvolved != null) candidates.add(ballInvolved.points);
    return candidates.reduce(max);
  }

  void potBall(Ball ball) {
    // Save snapshot for undo
    _history.add(_Action.snapshot(this));

    // Free ball: any nominated ball potted counts as 1, and does NOT reduce reds.
    if (freeBallActive) {
      _setScoreTurn(scoreTurn + 1);
      currentBreak += 1;
      _updateHighBreak();
      freeBallActive = false;

      // after a free ball (red-value), the striker must take a color
      expectingRed = false;
      return;
    }

    if (inColorsClearance) {
      _setScoreTurn(scoreTurn + ball.points);
      currentBreak += ball.points;
      _updateHighBreak();

      if (ball == nextColorInClearance) {
        nextColorInClearance = _nextClearanceBall(nextColorInClearance);
        if (ball == Ball.black) {
          // done (UI not locked in v1)
        }
      }
      return;
    }

    // reds phase
    if (expectingRed) {
      if (ball == Ball.red) {
        if (redsRemaining > 0) redsRemaining -= 1;
        _setScoreTurn(scoreTurn + 1);
        currentBreak += 1;
        _updateHighBreak();
        expectingRed = false; // now expect color
      } else {
        // "wrong" but we allow and user can undo + use foul
        _setScoreTurn(scoreTurn + ball.points);
        currentBreak += ball.points;
        _updateHighBreak();
        expectingRed = true;
      }
    } else {
      // expecting a color after a red
      if (ball == Ball.red) {
        _setScoreTurn(scoreTurn + 1);
        currentBreak += 1;
        _updateHighBreak();
        expectingRed = false;
      } else {
        _setScoreTurn(scoreTurn + ball.points);
        currentBreak += ball.points;
        _updateHighBreak();

        if (redsRemaining == 0) {
          inColorsClearance = true;
          nextColorInClearance = Ball.yellow;
        } else {
          expectingRed = true;
        }
      }
    }
  }

  void foul({required int pointsAwardedToOpponent, bool isMiss = false}) {
    _history.add(_Action.snapshot(this));
    _setScoreOpp(scoreOpp + pointsAwardedToOpponent);
    currentBreak = 0;
  }

  void activateFreeBall() {
    _history.add(_Action.snapshot(this));
    freeBallActive = true;
  }

  void switchTurn() {
    _history.add(_Action.snapshot(this));
    turn = turn.other;
    currentBreak = 0;
  }

  void undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    last.restoreInto(this);
  }

  void resetFrame() {
    scoreA = 0;
    scoreB = 0;
    turn = Player.a;
    redsRemaining = 15;
    inColorsClearance = false;
    nextColorInClearance = Ball.yellow;
    expectingRed = true;
    freeBallActive = false;
    currentBreak = 0;
    highBreakA = 0;
    highBreakB = 0;
    _history.clear();
  }

  Ball _nextClearanceBall(Ball b) {
    switch (b) {
      case Ball.yellow:
        return Ball.green;
      case Ball.green:
        return Ball.brown;
      case Ball.brown:
        return Ball.blue;
      case Ball.blue:
        return Ball.pink;
      case Ball.pink:
        return Ball.black;
      case Ball.black:
        return Ball.black;
      case Ball.red:
        return Ball.yellow;
    }
  }
}

class _Action {
  final int scoreA;
  final int scoreB;
  final Player turn;
  final int redsRemaining;
  final bool inColorsClearance;
  final Ball nextColorInClearance;
  final bool expectingRed;
  final bool freeBallActive;
  final int currentBreak;
  final int highBreakA;
  final int highBreakB;

  _Action({
    required this.scoreA,
    required this.scoreB,
    required this.turn,
    required this.redsRemaining,
    required this.inColorsClearance,
    required this.nextColorInClearance,
    required this.expectingRed,
    required this.freeBallActive,
    required this.currentBreak,
    required this.highBreakA,
    required this.highBreakB,
  });

  factory _Action.snapshot(FrameState s) => _Action(
    scoreA: s.scoreA,
    scoreB: s.scoreB,
    turn: s.turn,
    redsRemaining: s.redsRemaining,
    inColorsClearance: s.inColorsClearance,
    nextColorInClearance: s.nextColorInClearance,
    expectingRed: s.expectingRed,
    freeBallActive: s.freeBallActive,
    currentBreak: s.currentBreak,
    highBreakA: s.highBreakA,
    highBreakB: s.highBreakB,
  );

  void restoreInto(FrameState s) {
    s.scoreA = scoreA;
    s.scoreB = scoreB;
    s.turn = turn;
    s.redsRemaining = redsRemaining;
    s.inColorsClearance = inColorsClearance;
    s.nextColorInClearance = nextColorInClearance;
    s.expectingRed = expectingRed;
    s.freeBallActive = freeBallActive;
    s.currentBreak = currentBreak;
    s.highBreakA = highBreakA;
    s.highBreakB = highBreakB;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final FrameState state = FrameState();
  late final TabController tabs = TabController(length: 2, vsync: this);

  bool foulIsMiss = false;
  Ball foulBallOn = Ball.red;
  Ball foulBallInvolved = Ball.yellow;

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Snooker Score Calculator"),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(icon: Icon(Icons.scoreboard), text: "Score"),
            Tab(icon: Icon(Icons.rule), text: "Rules"),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          _ScoreTabRedesigned(
            state: state,
            foulIsMiss: foulIsMiss,
            foulBallOn: foulBallOn,
            foulBallInvolved: foulBallInvolved,
            onFoulIsMissChanged: (v) => setState(() => foulIsMiss = v),
            onFoulBallOnChanged: (b) => setState(() => foulBallOn = b),
            onFoulBallInvolvedChanged: (b) => setState(() => foulBallInvolved = b),
            onPot: (b) => setState(() => state.potBall(b)),
            onFreeBall: () => setState(() => state.activateFreeBall()),
            onQuickFoul: (p) => setState(() => state.foul(pointsAwardedToOpponent: p, isMiss: foulIsMiss)),
            onApplyRecommendedFoul: (p) =>
                setState(() => state.foul(pointsAwardedToOpponent: p, isMiss: foulIsMiss)),
            onUseExpectedBallOn: () {
              setState(() {
                foulBallOn = state.expectingRed && !state.inColorsClearance
                    ? Ball.red
                    : state.inColorsClearance
                    ? state.nextColorInClearance
                    : Ball.yellow;
              });
            },
            onSwitchTurn: () => setState(() => state.switchTurn()),
            onUndo: () => setState(() => state.undo()),
            onReset: () => _confirmReset(context),
            colorScheme: cs,
          ),
          const _rulesTab(),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset frame?"),
        content: const Text("This will clear scores, breaks, and restore 15 reds."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              setState(() => state.resetFrame());
              Navigator.pop(context);
            },
            child: const Text("Reset"),
          ),
        ],
      ),
    );
  }
}

/// NEW: Fully reorganized, responsive Score tab.
/// - Sticky “match header”
/// - Two-column layout on wide/landscape
/// - Bottom action bar for primary controls
/// - Pot/Foul actions presented as compact grids (mobile-friendly)
class _ScoreTabRedesigned extends StatelessWidget {
  final FrameState state;

  final bool foulIsMiss;
  final Ball foulBallOn;
  final Ball foulBallInvolved;

  final ValueChanged<bool> onFoulIsMissChanged;
  final ValueChanged<Ball> onFoulBallOnChanged;
  final ValueChanged<Ball> onFoulBallInvolvedChanged;

  final ValueChanged<Ball> onPot;
  final VoidCallback onFreeBall;

  final ValueChanged<int> onQuickFoul;
  final ValueChanged<int> onApplyRecommendedFoul;
  final VoidCallback onUseExpectedBallOn;

  final VoidCallback onSwitchTurn;
  final VoidCallback onUndo;
  final VoidCallback onReset;

  final ColorScheme colorScheme;

  const _ScoreTabRedesigned({
    required this.state,
    required this.foulIsMiss,
    required this.foulBallOn,
    required this.foulBallInvolved,
    required this.onFoulIsMissChanged,
    required this.onFoulBallOnChanged,
    required this.onFoulBallInvolvedChanged,
    required this.onPot,
    required this.onFreeBall,
    required this.onQuickFoul,
    required this.onApplyRecommendedFoul,
    required this.onUseExpectedBallOn,
    required this.onSwitchTurn,
    required this.onUndo,
    required this.onReset,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final isWide = width >= 780; // good breakpoint for tablets/landscape phones
      final padding = EdgeInsets.fromLTRB(16, 16, 16, 16 + _bottomBarHeight(context));

      final leftColumn = Column(
        children: [
          _SectionCard(
            title: "Pot",
            subtitle: "Tap a ball to add points to the player on turn.",
            child: _PotGrid(state: state, onPot: onPot, onFreeBall: onFreeBall),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: "Foul",
            subtitle: "Quick penalties or use the calculator for the recommended value.",
            child: _FoulPanel(
              state: state,
              foulIsMiss: foulIsMiss,
              foulBallOn: foulBallOn,
              foulBallInvolved: foulBallInvolved,
              onFoulIsMissChanged: onFoulIsMissChanged,
              onFoulBallOnChanged: onFoulBallOnChanged,
              onFoulBallInvolvedChanged: onFoulBallInvolvedChanged,
              onQuickFoul: onQuickFoul,
              onApplyRecommendedFoul: onApplyRecommendedFoul,
              onUseExpectedBallOn: onUseExpectedBallOn,
            ),
          ),
        ],
      );

      final rightColumn = Column(
        children: [
          _MatchHeader(state: state),
          const SizedBox(height: 12),
          _StatusOverview(state: state),
          const SizedBox(height: 12),
          _MiniHelpCard(state: state),
        ],
      );

      return Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: padding,
                  child: isWide
                      ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: rightColumn),
                      const SizedBox(width: 12),
                      Expanded(child: leftColumn),
                    ],
                  )
                      : Column(
                    children: [
                      rightColumn,
                      const SizedBox(height: 12),
                      leftColumn,
                    ],
                  ),
                ),
              ),
            ],
          ),
          _BottomActionBar(
            state: state,
            onSwitchTurn: onSwitchTurn,
            onUndo: onUndo,
            onReset: onReset,
          ),
        ],
      );
    });
  }

  double _bottomBarHeight(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return 72 + bottom; // bar height + safe area
  }
}

class _MatchHeader extends StatelessWidget {
  final FrameState state;
  const _MatchHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final isTurnA = state.turn == Player.a;
    final isTurnB = state.turn == Player.b;

    Widget scoreTile({
      required String label,
      required int score,
      required int high,
      required bool isTurn,
      required Alignment badgeAlignment,
    }) {
      return Expanded(
        child: Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                Align(
                  alignment: badgeAlignment,
                  child: AnimatedOpacity(
                    opacity: isTurn ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "ON",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(
                      "$score",
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text("High break: $high", style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        scoreTile(
          label: Player.a.label,
          score: state.scoreA,
          high: state.highBreakA,
          isTurn: isTurnA,
          badgeAlignment: Alignment.topRight,
        ),
        const SizedBox(width: 12),
        scoreTile(
          label: Player.b.label,
          score: state.scoreB,
          high: state.highBreakB,
          isTurn: isTurnB,
          badgeAlignment: Alignment.topRight,
        ),
      ],
    );
  }
}

class _StatusOverview extends StatelessWidget {
  final FrameState state;
  const _StatusOverview({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget pill(IconData icon, String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Status", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              state.expectedText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                pill(Icons.circle, "Reds left: ${state.redsRemaining}"),
                pill(Icons.timelapse, "Break: ${state.currentBreak}"),
                pill(
                  Icons.layers,
                  state.inColorsClearance ? "Phase: Clearance" : "Phase: Reds",
                ),
                if (state.freeBallActive) pill(Icons.star, "Free ball active"),
              ],
            ),
            if (state.inColorsClearance) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.flag, color: state.nextColorInClearance.color),
                  const SizedBox(width: 8),
                  Text(
                    "Next in order: ${state.nextColorInClearance.name}",
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _MiniHelpCard extends StatelessWidget {
  final FrameState state;
  const _MiniHelpCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final next = state.inColorsClearance
        ? "Clearance: pot ${state.nextColorInClearance.name} next."
        : state.expectingRed
        ? "Reds phase: you’re on a Red."
        : "Reds phase: you’re on a Color.";

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tips_and_updates),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                next,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.25),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PotGrid extends StatelessWidget {
  final FrameState state;
  final ValueChanged<Ball> onPot;
  final VoidCallback onFreeBall;

  const _PotGrid({required this.state, required this.onPot, required this.onFreeBall});

  @override
  Widget build(BuildContext context) {
    final balls = const [
      Ball.red,
      Ball.yellow,
      Ball.green,
      Ball.brown,
      Ball.blue,
      Ball.pink,
      Ball.black,
    ];

    return Column(
      children: [
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final cols = w >= 520 ? 4 : 3;
          final aspect = w >= 520 ? 1.8 : 1.9;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: balls.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspect,
            ),
            itemBuilder: (_, i) {
              final b = balls[i];
              final onText = b == Ball.black ? Colors.white : Colors.black;
              return FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: b.color,
                  foregroundColor: onText,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onPressed: () => onPot(b),
                icon: const Icon(Icons.sports_baseball, size: 18),
                label: Text("${b.name}\n+${b.points}", textAlign: TextAlign.center),
              );
            },
          );
        }),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.freeBallActive
                        ? "Free ball is active: next pot counts as 1 (as a red)."
                        : "Use Free ball only when a free ball is called by the referee.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onFreeBall,
                  icon: const Icon(Icons.star_outline),
                  label: Text(state.freeBallActive ? "Active" : "Free ball"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FoulPanel extends StatelessWidget {
  final FrameState state;

  final bool foulIsMiss;
  final Ball foulBallOn;
  final Ball foulBallInvolved;

  final ValueChanged<bool> onFoulIsMissChanged;
  final ValueChanged<Ball> onFoulBallOnChanged;
  final ValueChanged<Ball> onFoulBallInvolvedChanged;

  final ValueChanged<int> onQuickFoul;
  final ValueChanged<int> onApplyRecommendedFoul;
  final VoidCallback onUseExpectedBallOn;

  const _FoulPanel({
    required this.state,
    required this.foulIsMiss,
    required this.foulBallOn,
    required this.foulBallInvolved,
    required this.onFoulIsMissChanged,
    required this.onFoulBallOnChanged,
    required this.onFoulBallInvolvedChanged,
    required this.onQuickFoul,
    required this.onApplyRecommendedFoul,
    required this.onUseExpectedBallOn,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = state.suggestedFoulPoints(ballOn: foulBallOn, ballInvolved: foulBallInvolved);

    return Column(
      children: [
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final cols = w >= 520 ? 4 : 2;

          final quick = const [4, 5, 6, 7];
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: w >= 520 ? 2.6 : 3.2,
            children: quick
                .map(
                  (p) => FilledButton.icon(
                onPressed: () => onQuickFoul(p),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text("+$p to opponent"),
              ),
            )
                .toList(),
          );
        }),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text("Mark as MISS (info only)"),
          subtitle: const Text("Does not change points—just a label for your situation."),
          value: foulIsMiss,
          onChanged: onFoulIsMissChanged,
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text("Automatic foul calculator"),
          subtitle: Text("Recommended: $recommended points"),
          children: [
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                _BallDropdown(
                  label: "Ball on",
                  value: foulBallOn,
                  onChanged: onFoulBallOnChanged,
                ),
                _BallDropdown(
                  label: "Ball involved",
                  value: foulBallInvolved,
                  onChanged: onFoulBallInvolvedChanged,
                ),
                FilledButton.tonalIcon(
                  onPressed: onUseExpectedBallOn,
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text("Use expected ball on"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Recommended penalty: $recommended points to opponent",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Rule used: max(4, ball on, ball involved). Example: blue off the table = 5.",
                      style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.25),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => onApplyRecommendedFoul(recommended),
                        icon: const Icon(Icons.playlist_add_check),
                        label: const Text("Apply recommended foul"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Tip: In real snooker, foul points are at least 4, or the value of the ball 'on', or the ball fouled, up to 7.",
              style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.25),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ],
    );
  }
}

class _BallDropdown extends StatelessWidget {
  final String label;
  final Ball value;
  final ValueChanged<Ball> onChanged;

  const _BallDropdown({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Ball>(
            value: value,
            isExpanded: true,
            onChanged: (b) {
              if (b == null) return;
              onChanged(b);
            },
            items: Ball.values
                .map(
                  (b) => DropdownMenuItem(
                value: b,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: b.color, size: 14),
                    const SizedBox(width: 8),
                    Text("${b.name} (${b.points})"),
                  ],
                ),
              ),
            )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final FrameState state;
  final VoidCallback onSwitchTurn;
  final VoidCallback onUndo;
  final VoidCallback onReset;

  const _BottomActionBar({
    required this.state,
    required this.onSwitchTurn,
    required this.onUndo,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        elevation: 10,
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom * 0),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSwitchTurn,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text("Switch (${state.turn.other.label})"),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo),
                  tooltip: "Undo",
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  tooltip: "Reset frame",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _rulesTab extends StatelessWidget {
  const _rulesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _RuleCard(
          title: "Objective",
          body: "Score more points than your opponent in a frame. Points come from potting balls and from opponent fouls.",
        ),
        _RuleCard(
          title: "Ball values",
          body: "Red = 1. Colors: Yellow 2, Green 3, Brown 4, Blue 5, Pink 6, Black 7.",
        ),
        _RuleCard(
          title: "Normal sequence",
          body: "While reds remain: you alternate Red then Color. After potting a color (during reds phase) the color is re-spotted. Reds stay down.",
        ),
        _RuleCard(
          title: "After the last red",
          body: "Once all reds are gone and a color has been taken, colors are then potted in order: Yellow → Green → Brown → Blue → Pink → Black (no re-spot).",
        ),
        _RuleCard(
          title: "Fouls",
          body: "If you hit the wrong ball first, pot the cue ball, fail to hit any ball, or commit other fouls, your opponent gets points: minimum 4, or the value of the ball on / ball involved (up to 7).",
        ),
        _RuleCard(
          title: "Miss",
          body: "A referee can call 'miss' if you didn't make a good enough attempt to hit the ball on. The opponent may require the shot to be replayed from the original position. (This app marks MISS only as info in v1.)",
        ),
        _RuleCard(
          title: "Free ball",
          body: "If you are snookered after a foul, a free ball can be called. You may nominate any ball as a 'red': it scores 1 and is re-spotted, and then you must play a color.",
        ),
        _RuleCard(
          title: "Re-spotted colors",
          body: "During reds phase, any potted color is put back on its spot. If the spot is occupied, it goes to the nearest available spot (rules detail).",
        ),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  final String title;
  final String body;

  const _RuleCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
