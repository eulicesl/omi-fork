import Foundation

/// A deterministic script of bridge events with logical timestamps. The
/// fake bridge runs scripts; scripts themselves carry no behavior.
struct FakeBridgeScript: Equatable {
  let name: String
  let events: [Timed]

  struct Timed: Equatable {
    let atMs: Int
    let event: FakeBridgeEvent
  }
}

/// The 10 named failure scenarios PR 0b commits to, plus a happy-path
/// baseline. Each factory returns a fresh `FakeBridgeScript` so callers
/// can mutate without aliasing.
///
/// Scenario inventory (per roadmap PR 0b):
/// 1. firstTokenDelay         — long gap before first text delta
/// 2. midStreamStall          — deltas then silence
/// 3. neverReturningTool      — tool_use with no matching activity-end
/// 4. malformedMessage        — bad line in the stream
/// 5. bridgeCrashMidTurn      — subprocess dies mid-turn
/// 6. heartbeatLoss           — heartbeats stop arriving (PR 8 prep)
/// 7. authRequired            — auth_required event before result
/// 8. interruptDuringTool     — interrupt arrives while a tool is running
/// 9. delayedFinalResult      — deltas complete but result is late
/// 10. emptyToolResult        — tool returns with no output content
enum FakeBridgeScenario {

  // MARK: - Baseline

  /// init → 3 text deltas → result. No stalls, no tools. Sanity baseline
  /// the determinism test uses as a control.
  static func happyPath() -> FakeBridgeScript {
    FakeBridgeScript(
      name: "happy_path",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(100, .textDelta(text: "Hello")),
        at(200, .textDelta(text: " world")),
        at(300, .textDelta(text: ".")),
        at(400, .result(
          text: "Hello world.",
          sessionId: "fake-session",
          costUsd: 0.001,
          inputTokens: 10, outputTokens: 3,
          cacheReadTokens: 0, cacheWriteTokens: 0
        )),
      ]
    )
  }

  // MARK: - Failure scenarios

  /// First text delta arrives after `ms`. Everything else is normal.
  static func firstTokenDelay(ms: Int = 12_000) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "first_token_delay",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(ms, .textDelta(text: "Sorry for the wait.")),
        at(ms + 100, .result(
          text: "Sorry for the wait.",
          sessionId: "fake-session",
          costUsd: 0.001,
          inputTokens: 10, outputTokens: 5,
          cacheReadTokens: 0, cacheWriteTokens: 0
        )),
      ]
    )
  }

  /// `deltasBeforeStall` deltas then `stallDurationMs` of silence, then
  /// resumes and completes. Mirrors a model upstream hiccup that recovers.
  static func midStreamStall(
    deltasBeforeStall: Int = 3,
    stallDurationMs: Int = 30_000
  ) -> FakeBridgeScript {
    var events: [FakeBridgeScript.Timed] = [
      at(0, .initSession(sessionId: "fake-session"))
    ]
    var t = 100
    for i in 0..<deltasBeforeStall {
      events.append(at(t, .textDelta(text: "chunk\(i) ")))
      t += 100
    }
    let resumeAt = t + stallDurationMs
    events.append(at(resumeAt, .textDelta(text: "back.")))
    events.append(at(resumeAt + 100, .result(
      text: "stalled then back.",
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10, outputTokens: deltasBeforeStall + 1,
      cacheReadTokens: 0, cacheWriteTokens: 0
    )))
    return FakeBridgeScript(name: "mid_stream_stall", events: events)
  }

  /// A tool_use is emitted, a tool_activity start follows, then nothing
  /// — no result, no tool_activity end, no further deltas. Drives PR 3
  /// per-tool timeout tests.
  static func neverReturningTool(
    toolName: String = "execute_sql",
    waitMs: Int = 60_000
  ) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "never_returning_tool",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(50, .textDelta(text: "Let me look that up.")),
        at(100, .toolUse(
          callId: "call-1",
          name: toolName,
          input: ["sql": "SELECT 1"]
        )),
        at(150, .toolActivity(
          name: toolName,
          status: "started",
          toolUseId: "call-1",
          input: ["sql": "SELECT 1"]
        )),
        // No further events for the next `waitMs`. The script terminates
        // without a result; the fake reports `.neverTerminated`.
        at(150 + waitMs, .error(message: "fake_scenario_never_returning_tool")),
      ]
    )
  }

  /// A line that isn't valid JSON appears in the stream. Real bridge logs
  /// and skips. Tests assert the consumer keeps draining and reaches the
  /// final result.
  static func malformedMessage(beforeMs: Int = 100) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "malformed_message",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(beforeMs, .malformed(rawLine: "{this is not valid json")),
        at(beforeMs + 100, .textDelta(text: "Recovered.")),
        at(beforeMs + 200, .result(
          text: "Recovered.",
          sessionId: "fake-session",
          costUsd: 0.001,
          inputTokens: 10, outputTokens: 1,
          cacheReadTokens: 0, cacheWriteTokens: 0
        )),
      ]
    )
  }

  /// Some deltas then `bridgeCrash`. No result. Tests assert consumers
  /// surface this as bridge-unavailable rather than a hang.
  static func bridgeCrashMidTurn(afterMs: Int = 500) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "bridge_crash_mid_turn",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(100, .textDelta(text: "Working on it…")),
        at(afterMs, .bridgeCrash),
      ]
    )
  }

  /// `initialHeartbeats` heartbeats arrive at `intervalMs`, then nothing.
  /// PR 8's detector should flip to `.bridgeUnresponsive` after the
  /// configured threshold.
  static func heartbeatLoss(
    initialHeartbeats: Int = 2,
    intervalMs: Int = 5_000
  ) -> FakeBridgeScript {
    var events: [FakeBridgeScript.Timed] = [
      at(0, .initSession(sessionId: "fake-session")),
      at(50, .textDelta(text: "Thinking…")),
    ]
    for i in 1...initialHeartbeats {
      events.append(at(i * intervalMs, .heartbeat(
        uptimeMs: i * intervalMs,
        upstreamLastEventMs: 50
      )))
    }
    // No further heartbeats and no result.
    return FakeBridgeScript(name: "heartbeat_loss", events: events)
  }

  /// `auth_required` arrives before any deltas. PR 4 maps this to the
  /// auth-required error card.
  static func authRequired(beforeMs: Int = 100) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "auth_required",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(beforeMs, .authRequired(
          methods: ["agent_auth", "env_var"],
          authUrl: "https://example.test/oauth"
        )),
      ]
    )
  }

  /// tool_use → tool_activity start → (interrupt arrives at
  /// `interruptAfterMs`). Tests schedule the interrupt via
  /// `FakeAgentBridge.scheduleInterrupt(atMs:)`.
  static func interruptDuringTool(
    toolName: String = "execute_sql",
    interruptAfterMs: Int = 2_000
  ) -> FakeBridgeScript {
    FakeBridgeScript(
      name: "interrupt_during_tool",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(50, .toolUse(
          callId: "call-1",
          name: toolName,
          input: ["sql": "SELECT slow()"]
        )),
        at(100, .toolActivity(
          name: toolName,
          status: "started",
          toolUseId: "call-1",
          input: ["sql": "SELECT slow()"]
        )),
        // Long pause; test interrupts before this finishes.
        at(interruptAfterMs + 10_000, .toolActivity(
          name: toolName,
          status: "completed",
          toolUseId: "call-1",
          input: nil
        )),
      ]
    )
  }

  /// `deltasMs` deltas complete by their times, then a long pause before
  /// the result event. Tests final-result latency tracking.
  static func delayedFinalResult(
    deltasMs: [Int] = [100, 200, 300],
    resultMs: Int = 8_000
  ) -> FakeBridgeScript {
    var events: [FakeBridgeScript.Timed] = [
      at(0, .initSession(sessionId: "fake-session"))
    ]
    for (i, t) in deltasMs.enumerated() {
      events.append(at(t, .textDelta(text: "d\(i) ")))
    }
    events.append(at(resultMs, .result(
      text: deltasMs.indices.map { "d\($0) " }.joined(),
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10, outputTokens: deltasMs.count,
      cacheReadTokens: 0, cacheWriteTokens: 0
    )))
    return FakeBridgeScript(name: "delayed_final_result", events: events)
  }

  /// Tool runs and returns immediately but produces no output content.
  /// Used by PR 4 to verify the "no data found" recovery card and by
  /// PR 7 scenario 5.
  static func emptyToolResult(toolName: String = "execute_sql") -> FakeBridgeScript {
    FakeBridgeScript(
      name: "empty_tool_result",
      events: [
        at(0, .initSession(sessionId: "fake-session")),
        at(50, .toolUse(
          callId: "call-1",
          name: toolName,
          input: ["sql": "SELECT 1 WHERE 0"]
        )),
        at(100, .toolActivity(
          name: toolName,
          status: "started",
          toolUseId: "call-1",
          input: nil
        )),
        at(120, .toolActivity(
          name: toolName,
          status: "completed",
          toolUseId: "call-1",
          input: nil
        )),
        at(130, .toolResultDisplay(
          toolUseId: "call-1",
          name: toolName,
          output: ""
        )),
        at(200, .textDelta(text: "I don't have anything on that.")),
        at(300, .result(
          text: "I don't have anything on that.",
          sessionId: "fake-session",
          costUsd: 0.0005,
          inputTokens: 10, outputTokens: 8,
          cacheReadTokens: 0, cacheWriteTokens: 0
        )),
      ]
    )
  }

  // MARK: - Inventory

  /// All scenarios in declaration order. Tests iterate this to apply the
  /// determinism contract to every scenario without per-scenario boilerplate.
  static func all() -> [FakeBridgeScript] {
    [
      happyPath(),
      firstTokenDelay(),
      midStreamStall(),
      neverReturningTool(),
      malformedMessage(),
      bridgeCrashMidTurn(),
      heartbeatLoss(),
      authRequired(),
      interruptDuringTool(),
      delayedFinalResult(),
      emptyToolResult(),
    ]
  }

  // MARK: - Internal

  private static func at(_ ms: Int, _ event: FakeBridgeEvent) -> FakeBridgeScript.Timed {
    FakeBridgeScript.Timed(atMs: ms, event: event)
  }
}
