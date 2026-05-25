import Foundation

// MARK: - ChatErrorState
//
// Scaffolding for PR 4 (Error recovery UX). Defines the five user-visible
// failure classes the chat surface needs explicit, recoverable UI for.
//
// This file is intentionally not yet wired into `ChatProvider` / `ChatPage` /
// `AgentBridge`. The replacement of the existing inline `errorMessage` banner,
// `BrowserExtensionSetup` sheet, and bridge-failure assigns happens in the
// follow-up PR once PR 3's timeout plumbing lands.
//
// Out of scope for PR 4 (kept as separate sheets):
//   - `ClaudeAuthSheet`              ($199 paywall flow, not a generic error)
//   - `showOmiThresholdAlert`        (similar paywall)

/// Why the bridge process is unavailable. Used to drive copy + the
/// "Install runtime" vs "Quit & Reopen" CTA split.
enum BridgeUnavailableReason: Equatable, Sendable {
  /// Node.js binary not found on PATH (e.g. fresh install, dev build before
  /// `./run.sh`). Maps from `BridgeError.nodeNotFound`.
  case nodeMissing
  /// Bridge JS / AI components not on disk. Maps from
  /// `BridgeError.bridgeScriptNotFound`.
  case runtimeMissing
  /// Bridge process started but exited / OOM'd. Maps from
  /// `BridgeError.processExited` and `.outOfMemory`.
  case crashed
  /// Catch-all for "we don't know why it's not running"; maps from
  /// `BridgeError.notRunning` and any other un-classified start failure.
  case unknown
}

/// The five recoverable error states the chat UI renders inline.
///
/// Anything that does NOT map to a case here (e.g. `BridgeError.encodingError`,
/// `.quotaExceeded`, `.agentError`, `.authMissing` for the paywall variant)
/// is intentionally left to the existing `errorMessage` banner / sheets. The
/// `from(_:)` factory returns `nil` in those cases so callers can fall through.
enum ChatErrorState: Equatable, Sendable {
  /// Token expired or the bridge emitted `auth_required` mid-turn. Recovery:
  /// re-sign-in. Distinct from the Claude OAuth paywall.
  case authRequired

  /// Per-turn or per-tool timeout from PR 3. `toolName` is the offending tool
  /// when the timeout was scoped (nil = full-turn timeout).
  case timeout(toolName: String?)

  /// Bridge process can't run. Reason picks the CTA: nodeMissing /
  /// runtimeMissing → "Install runtime"; crashed / unknown → "Quit & Reopen".
  case bridgeUnavailable(reason: BridgeUnavailableReason)

  /// User pressed Stop / Cancel mid-turn. Recovery: resume (replay last
  /// user turn with a fresh `turnId`) or discard.
  case interrupted

  /// Tools returned empty payloads and the model produced no text. Recovery:
  /// nudge the user to try a different question instead of an infinite spinner.
  case noDataFound
}

// MARK: - Recovery actions

/// One primary recovery action per error card. Multiple cases may share the
/// same recovery (e.g. timeout + interrupted both → retry) — that's intentional.
enum ChatErrorRecoveryAction: Equatable, Sendable {
  /// Replay the last user turn with a fresh `turnId`.
  case retry
  /// Open the sign-in flow (Firebase / OAuth, NOT the $199 Claude paywall).
  case signIn
  /// Open Settings (e.g. for switching to a different model / mode).
  case openSettings
  /// Show installation instructions for the bridge runtime (Node.js / AI
  /// components). Currently routes to a docs URL; PR 4 may surface a sheet.
  case installRuntime
  /// Dismiss the card with no further action.
  case dismiss
  /// Switch bridge mode (e.g. fall back from `userClaude` to `piMono`).
  case switchMode
}

extension ChatErrorState {
  /// The single primary CTA shown on the error card.
  ///
  /// Design note: we deliberately surface only ONE recovery per card. A
  /// "Show details" disclosure can offer secondary affordances, but the card
  /// itself stays scannable.
  var primaryRecovery: ChatErrorRecoveryAction {
    switch self {
    case .authRequired:
      return .signIn
    case .timeout:
      return .retry
    case .bridgeUnavailable(let reason):
      switch reason {
      case .nodeMissing, .runtimeMissing:
        return .installRuntime
      case .crashed, .unknown:
        // "Quit & Reopen" maps to .retry today — the card copy says
        // "Quit & Reopen" but the action is functionally a retry-after-
        // restart. We can introduce a `.relaunch` case later if needed.
        return .retry
      }
    case .interrupted:
      return .retry
    case .noDataFound:
      return .dismiss
    }
  }
}

// MARK: - BridgeError mapping

extension ChatErrorState {
  /// Lift a `BridgeError` into a `ChatErrorState` when one of the five
  /// recoverable cases applies. Returns `nil` for errors that should keep
  /// flowing into the existing `errorMessage` banner (encoding errors,
  /// quota / paywall, generic agent errors).
  ///
  /// Cases handled:
  ///   - `.timeout`              → `.timeout(toolName: nil)`
  ///   - `.stopped`              → `.interrupted`
  ///   - `.nodeNotFound`         → `.bridgeUnavailable(.nodeMissing)`
  ///   - `.bridgeScriptNotFound` → `.bridgeUnavailable(.runtimeMissing)`
  ///   - `.processExited`        → `.bridgeUnavailable(.crashed)`
  ///   - `.outOfMemory`          → `.bridgeUnavailable(.crashed)`
  ///   - `.notRunning`           → `.bridgeUnavailable(.unknown)`
  ///   - `.authMissing`          → `.authRequired`
  ///
  /// Cases intentionally returning `nil` (fall through to existing banner):
  ///   - `.encodingError`        (internal error, retry won't help)
  ///   - `.quotaExceeded`        (paywall — kept as separate sheet)
  ///   - `.agentError`           (varied; existing banner already classifies)
  static func from(_ bridgeError: BridgeError) -> ChatErrorState? {
    switch bridgeError {
    case .timeout:
      return .timeout(toolName: nil)
    case .stopped:
      return .interrupted
    case .nodeNotFound:
      return .bridgeUnavailable(reason: .nodeMissing)
    case .bridgeScriptNotFound:
      return .bridgeUnavailable(reason: .runtimeMissing)
    case .processExited, .outOfMemory:
      return .bridgeUnavailable(reason: .crashed)
    case .notRunning:
      return .bridgeUnavailable(reason: .unknown)
    case .authMissing:
      return .authRequired
    case .encodingError, .quotaExceeded, .agentError:
      return nil
    }
  }
}
