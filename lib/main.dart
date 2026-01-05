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
      // only allow the next required color (we still let user pot something else, but that's "wrong" — they should use foul)
      // We'll accept it but treat as that ball's points and advance if it matches order.
      _setScoreTurn(scoreTurn + ball.points);
      currentBreak += ball.points;
      _updateHighBreak();

      if (ball == nextColorInClearance) {
        // advance order
        nextColorInClearance = _nextClearanceBall(nextColorInClearance);
        if (nextColorInClearance == Ball.black) {
          // still needs black next
        }
        // if just potted black (and it was next), the frame is effectively done (we don't lock UI here)
        if (ball == Ball.black) {
          // done
        }
      }
      return;
    }

    // reds phase
    if (expectingRed) {
      // potted a red (normally)
      if (ball == Ball.red) {
        if (redsRemaining > 0) redsRemaining -= 1;
        _setScoreTurn(scoreTurn + 1);
        currentBreak += 1;
        _updateHighBreak();
        expectingRed = false; // now expect color
        // if reds now 0, still need a color after last red; after that, go to clearance
      } else {
        // If they pot a color when expecting red -> should be foul normally.
        // We still record it as points (user can undo and use foul).
        _setScoreTurn(scoreTurn + ball.points);
        currentBreak += ball.points;
        _updateHighBreak();
        expectingRed = true; // usually remains red, but we keep it simple
      }
    } else {
      // expecting a color after a red
      if (ball == Ball.red) {
        // red when expecting color -> should be foul normally
        _setScoreTurn(scoreTurn + 1);
        currentBreak += 1;
        _updateHighBreak();
        expectingRed = false;
      } else {
        _setScoreTurn(scoreTurn + ball.points);
        currentBreak += ball.points;
        _updateHighBreak();

        // After taking a color in reds phase:
        if (redsRemaining == 0) {
          // move into clearance phase (yellow next)
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

    // foul ends break
    currentBreak = 0;

    // miss doesn't change points; it's informational (could be logged)
    // we keep it for display via history only (not necessary for v1)
  }

  void activateFreeBall() {
    _history.add(_Action.snapshot(this));
    freeBallActive = true;
  }

  void switchTurn() {
    _history.add(_Action.snapshot(this));
    // switching turn ends current break for the new player
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
          _scoreTab(cs),
          const _rulesTab(),
        ],
      ),
    );
  }

  Widget _scoreTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _scoreHeader(),
        const SizedBox(height: 12),
        _statusCard(),
        const SizedBox(height: 12),
        _potButtons(),
        const SizedBox(height: 12),
        _foulButtons(),
        const SizedBox(height: 16),
        _controlsRow(),
      ],
    );
  }

  Widget _scoreHeader() {
    Widget playerCard(Player p) {
      final isTurn = state.turn == p;
      final score = p == Player.a ? state.scoreA : state.scoreB;
      final high = p == Player.a ? state.highBreakA : state.highBreakB;

      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      p.label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                    if (isTurn)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          "TURN",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "$score",
                  style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text("High break: $high", style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        playerCard(Player.a),
        const SizedBox(width: 12),
        playerCard(Player.b),
      ],
    );
  }

  Widget _statusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.expectedText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _chip("Reds left: ${state.redsRemaining}"),
                _chip(state.inColorsClearance ? "Phase: Colors clearance" : "Phase: Reds + colors"),
                _chip("Current break: ${state.currentBreak}"),
              ],
            ),
            if (state.inColorsClearance) ...[
              const SizedBox(height: 10),
              Text("Next color in order: ${state.nextColorInClearance.name}",
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(t),
    );
  }

  Widget _potButtons() {
    List<Ball> balls = const [
      Ball.red,
      Ball.yellow,
      Ball.green,
      Ball.brown,
      Ball.blue,
      Ball.pink,
      Ball.black
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Pot", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: balls.map((b) {
                return ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: b.color,
                    foregroundColor: b == Ball.black ? Colors.white : Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: () => setState(() => state.potBall(b)),
                  icon: const Icon(Icons.sports_baseball, size: 18),
                  label: Text("${b.name} (+${b.points})"),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => state.activateFreeBall()),
                  icon: const Icon(Icons.star_outline),
                  label: const Text("Free ball"),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Use only when a free ball is called. Next pot = 1 point (as a red), then you must take a color.",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _foulButtons() {
    final foulPoints = [4, 5, 6, 7];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Foul", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: foulPoints.map((p) {
                return ElevatedButton.icon(
                  onPressed: () => setState(() => state.foul(pointsAwardedToOpponent: p, isMiss: foulIsMiss)),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text("$p points to opponent"),
                );
              }).toList(),
            ),
            const Divider(height: 22),
            Row(
              children: [
                const Icon(Icons.calculate, size: 18),
                const SizedBox(width: 8),
                Text(
                  "Automatic foul calculator",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ballDropdown(
                  label: "Ball on",
                  value: foulBallOn,
                  onChanged: (b) => setState(() => foulBallOn = b!),
                ),
                _ballDropdown(
                  label: "Ball involved",
                  value: foulBallInvolved,
                  onChanged: (b) => setState(() => foulBallInvolved = b!),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      foulBallOn = state.expectingRed && !state.inColorsClearance
                          ? Ball.red
                          : state.inColorsClearance
                              ? state.nextColorInClearance
                              : Ball.yellow;
                    });
                  },
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text("Use expected ball on"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final autoPoints = state.suggestedFoulPoints(ballOn: foulBallOn, ballInvolved: foulBallInvolved);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Recommended penalty: $autoPoints points to opponent",
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Uses max(4, ball on, ball involved). Example: knocking the blue off the table = 5 points.",
                      style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.25),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => setState(() => state.foul(pointsAwardedToOpponent: autoPoints, isMiss: foulIsMiss)),
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text("Apply recommended foul"),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            "Next expected shot: ${state.expectedText}. Switch turn or request a replay based on your decision.",
                            style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Mark foul as MISS (info only)"),
              value: foulIsMiss,
              onChanged: (v) => setState(() => foulIsMiss = v),
            ),
            const Text(
              "Tip: In real snooker, foul points are at least 4, or the value of the ball 'on', or the ball fouled, up to 7.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ballDropdown({required String label, required Ball value, required ValueChanged<Ball?> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 4),
        DropdownButton<Ball>(
          value: value,
          onChanged: onChanged,
          items: Ball.values
              .map(
                (b) => DropdownMenuItem(
                  value: b,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: b.color, size: 14),
                      const SizedBox(width: 6),
                      Text("${b.name} (${b.points})"),
                    ],
                  ),
                ),
              )
              .toList(),
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.black),
          dropdownColor: Colors.white,
        ),
      ],
    );
  }

  Widget _controlsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: () => setState(() => state.switchTurn()),
          icon: const Icon(Icons.swap_horiz),
          label: const Text("Switch turn"),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() => state.undo()),
          icon: const Icon(Icons.undo),
          label: const Text("Undo"),
        ),
        OutlinedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Reset frame?"),
                content: const Text("This will clear scores, breaks, and restore 15 reds."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => state.resetFrame());
                      Navigator.pop(context);
                    },
                    child: const Text("Reset"),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text("Reset frame"),
        ),
      ],
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
          body:
          "Score more points than your opponent in a frame. Points come from potting balls and from opponent fouls.",
        ),
        _RuleCard(
          title: "Ball values",
          body:
          "Red = 1. Colors: Yellow 2, Green 3, Brown 4, Blue 5, Pink 6, Black 7.",
        ),
        _RuleCard(
          title: "Normal sequence",
          body:
          "While reds remain: you alternate Red then Color. After potting a color (during reds phase) the color is re-spotted. Reds stay down.",
        ),
        _RuleCard(
          title: "After the last red",
          body:
          "Once all reds are gone and a color has been taken, colors are then potted in order: Yellow → Green → Brown → Blue → Pink → Black (no re-spot).",
        ),
        _RuleCard(
          title: "Fouls",
          body:
          "If you hit the wrong ball first, pot the cue ball, fail to hit any ball, or commit other fouls, your opponent gets points: minimum 4, or the value of the ball on / ball involved (up to 7).",
        ),
        _RuleCard(
          title: "Miss",
          body:
          "A referee can call 'miss' if you didn't make a good enough attempt to hit the ball on. The opponent may require the shot to be replayed from the original position. (This app marks MISS only as info in v1.)",
        ),
        _RuleCard(
          title: "Free ball",
          body:
          "If you are snookered after a foul, a free ball can be called. You may nominate any ball as a 'red': it scores 1 and is re-spotted, and then you must play a color.",
        ),
        _RuleCard(
          title: "Re-spotted colors",
          body:
          "During reds phase, any potted color is put back on its spot. If the spot is occupied, it goes to the nearest available spot (rules detail).",
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
