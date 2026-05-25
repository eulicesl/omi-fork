import Foundation

/// Time thresholds the `StallDetector` uses to promote inter-event gaps
/// and per-tool durations between `.running`, `.slow`, and `.stalled`.
///
/// Values here are first-pass guesses for V1. PR 9 (`Sprint exit review
/// + threshold tuning`, per `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md`)
/// replaces them with p90/p99 cuts of real telemetry. Keep the struct
/// fully `Sendable` + `Equatable` so PR 9's tuning PR is a trivial
/// constants update with no behavioral churn.
struct StallThresholds: Sendable, Equatable {
  /// A gap (inter-event or per-tool) reaching this length promotes to
  /// `.slow`. The UI surfaces a "still working…" annotation.
  let slowGapMs: Int

  /// A gap reaching this length promotes to `.stalled`. The UI surfaces
  /// a message-level banner offering Cancel (wired to
  /// `AgentBridge.interrupt()` by Commit C/D of PR 1).
  let stalledGapMs: Int

  init(slowGapMs: Int, stalledGapMs: Int) {
    precondition(
      slowGapMs > 0 && stalledGapMs > slowGapMs,
      "stalledGapMs must be > slowGapMs > 0"
    )
    self.slowGapMs = slowGapMs
    self.stalledGapMs = stalledGapMs
  }

  /// V1 ship defaults. Slow at 8s, stalled at 20s. PR 9 tunes these
  /// against real `interEventGapsMs` and `toolDurationsMs` distributions
  /// captured by PR 0a telemetry.
  static let v1Defaults = StallThresholds(slowGapMs: 8_000, stalledGapMs: 20_000)
}
