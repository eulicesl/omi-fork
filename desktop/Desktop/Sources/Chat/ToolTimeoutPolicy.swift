import Foundation

/// Per-tool timeout ceilings for the chat agent's tool calls.
///
/// Applies only to **piMono** mode (the assistant's 7 built-in tools).
/// `userClaude` mode (Claude Code / Bash / file-system tools) is
/// explicitly carved out — those tools legitimately take longer and
/// V1 doesn't time them out aggressively. The full userClaude tool
/// execution contract is V2 work (per
/// `MACOS_CHAT_RELIABILITY_ROADMAP.md`).
///
/// On timeout, the calling code emits a synthetic `tool_result` back
/// to the bridge with an error string. The model receives the error
/// like any other tool result and can respond accordingly (retry with
/// a different approach, surface the issue, etc.). The UI block for
/// that tool flips to `.failed` so the user sees a red xmark instead
/// of an unresolving spinner.
///
/// The turn-level `chat.turn.completed` outcome stays `.completed` for
/// "one tool timed out but the model recovered" — the per-tool failure
/// is recorded inside the message's content blocks, not at the turn
/// level. Turn-level `.timeout` outcome is reserved for whole-turn
/// `BridgeError.timeout` cases.
struct ToolTimeoutPolicy: Sendable, Equatable {
  /// Per-tool ceilings, keyed by the **clean** tool name (after any
  /// `mcp__` prefix stripping). Values in seconds.
  let timeoutsSeconds: [String: Int]

  /// Applied to any tool name not in `timeoutsSeconds`. Conservatively
  /// long because unknown tools may legitimately be slow; the goal is
  /// to catch hangs, not throttle. PR 9 tunes against telemetry.
  let defaultSeconds: Int

  /// Look up the timeout for `toolName`. Strips the `mcp__` prefix
  /// using the existing convention from `ChatProvider.swift:97-99` /
  /// `AnalyticsManager.chatToolCallCompleted` so policy keys can be
  /// the bare tool names regardless of how the bridge labels them.
  func seconds(for toolName: String) -> Int {
    let cleanName: String
    if toolName.hasPrefix("mcp__") {
      cleanName = String(toolName.split(separator: "__").last ?? Substring(toolName))
    } else {
      cleanName = toolName
    }
    return timeoutsSeconds[cleanName] ?? defaultSeconds
  }

  /// V1 ship defaults (per the roadmap doc's PR 3 table). PR 9 tunes
  /// against real `toolDurationsMs` distributions from PR 0a telemetry
  /// at `p95(toolDurationsMs[name] | outcome=completed) × 1.5`.
  static let v1Defaults = ToolTimeoutPolicy(
    timeoutsSeconds: [
      "execute_sql": 15,
      "semantic_search": 20,
      "search_tasks": 20,
      "get_daily_recap": 25,
      "complete_task": 5,
      "delete_task": 5,
      "save_knowledge_graph": 30,
    ],
    defaultSeconds: 60
  )
}

/// Errors that can be returned from `withToolTimeout`. The timeout
/// case is a normal classification, not exceptional — callers
/// pattern-match on it to emit the synthetic-error response to the
/// bridge.
enum ToolTimeoutOutcome<Success: Sendable>: Sendable {
  case success(Success)
  case timedOut(elapsedSeconds: Int)
}

/// Run `operation` with a deadline. Returns `.success` if `operation`
/// completes within `seconds`, `.timedOut` otherwise. The operation
/// task is cancelled on timeout — well-behaved tools that check
/// `Task.isCancelled` will stop work; tools that don't will continue
/// running in the background until they finish naturally (their
/// result is discarded). Acceptable trade-off for V1 since the
/// bridge has already received the synthetic-error response.
func withToolTimeout<Success: Sendable>(
  seconds: Int,
  operation: @Sendable @escaping () async -> Success
) async -> ToolTimeoutOutcome<Success> {
  await withTaskGroup(of: ToolTimeoutOutcome<Success>.self) { group in
    group.addTask {
      .success(await operation())
    }
    group.addTask {
      // Sleep can throw on cancellation; treat that as "operation
      // finished first and cancelled us" — sleeping arm returns the
      // timeout case only if it ran to completion.
      do {
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        return .timedOut(elapsedSeconds: seconds)
      } catch {
        // Cancelled — return a sentinel the loser-cancel handles.
        // The first-result branch below ignores this when the
        // operation task already returned.
        return .timedOut(elapsedSeconds: seconds)
      }
    }
    let result = await group.next()!
    group.cancelAll()
    return result
  }
}
