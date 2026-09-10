/// Pure A-B loop state machine (unit-tested). The player mirrors these
/// phases onto MPV's native `ab-loop-a` / `ab-loop-b` properties.
enum AbPhase { off, aSet, abSet }

class AbState {
  const AbState({required this.phase, this.aMs, this.bMs});

  final AbPhase phase;
  final int? aMs;
  final int? bMs;

  static const off = AbState(phase: AbPhase.off);

  /// What the next tap on the "A-B loop" row should become at [nowMs].
  AbState advance(int nowMs) {
    switch (phase) {
      case AbPhase.off:
        return AbState(phase: AbPhase.aSet, aMs: nowMs);
      case AbPhase.aSet:
        final a = aMs!;
        final b = nowMs > a ? nowMs : a + 1000; // guard: min 1s window
        return AbState(phase: AbPhase.abSet, aMs: a, bMs: b);
      case AbPhase.abSet:
        return off;
    }
  }

  /// Short label for the settings row, MX-style.
  String describe() {
    switch (phase) {
      case AbPhase.off:
        return 'Off - tap to mark point A';
      case AbPhase.aSet:
        return 'A set - tap to mark B | long-press to cancel';
      case AbPhase.abSet:
        return 'Looping A → B | tap to clear';
    }
  }
}
