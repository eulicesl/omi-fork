import Foundation

// MARK: - TaskLifecycleScenario (PR 7 scaffolding)
//
// Scenario #3 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Multi-step lifecycle: create → list → complete. Validates that:
//   1. The model creates an action_item via the appropriate tool (typically
//      `staged_tasks`-related, but `execute_sql` is also accepted if the
//      runtime tool registry lacks a dedicated create-task tool).
//   2. A subsequent "list my tasks" prompt surfaces the newly-created
//      item.
//   3. A "mark X complete" prompt updates the row's `completed` field
//      to true.
//   4. Each turn completes within `Self.turnTimeoutSeconds`.
//
// Distinct from #1 and #2 because it exercises chat's write path —
// confirming PR 5's saveMessage-vs-poll race fix holds across multi-
// turn writes that ALL hit the same action_items row.

enum TaskLifecycleScenario: ChatScenario {
  static let id = "task_lifecycle"

  static let description =
    "Create a task via chat, list tasks, mark it complete — assert each " +
    "turn succeeds and the action_items row reflects the final state."

  /// Three prompts run in sequence within a single turn-group. Each
  /// has its own assertion gate; the scenario fails if any individual
  /// turn fails.
  static let createPrompt = "remind me to verify the chat-reliability scenario suite"
  static let listPrompt = "show me my tasks"
  static let completePrompt = "mark the chat-reliability scenario task complete"

  /// Title fragment the model should produce or echo back. Loose
  /// match — the model phrases the title many ways.
  static let expectedTitleFragment = "chat-reliability scenario"

  static let turnTimeoutSeconds: Int = 30

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .capability)
  }
}
