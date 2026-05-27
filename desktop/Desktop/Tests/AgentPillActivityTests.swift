import XCTest
@testable import Omi_Computer

/// Pins `AgentPillsManager.describeActivity` so the floating-bar pill never
/// regresses to displaying mid-stream partial text tokens (the "B…/typin…"
/// bug from the original screenshots).
@MainActor
final class AgentPillActivityTests: XCTestCase {

    // MARK: - Streaming text suppression

    /// While the AI message is still streaming, partial text chunks must NOT
    /// drive `latestActivity`. The pill bar is line-limited, so a chunk like
    /// `"O"` would render as `"O…"` and a chunk like `"typing the response"`
    /// would render mid-word. Fall back to "Working…" until tools or final
    /// text arrive.
    func testStreamingTextOnlyMessageFallsBackToWorking() {
        let message = ChatMessage(
            text: "B",
            sender: .ai,
            isStreaming: true,
            contentBlocks: [.text(id: "t1", text: "B")]
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Working…")
    }

    func testStreamingMidWordChunkFallsBackToWorking() {
        let message = ChatMessage(
            text: "typin",
            sender: .ai,
            isStreaming: true,
            contentBlocks: [.text(id: "t1", text: "typin")]
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Working…")
    }

    func testStreamingPartialSentenceFallsBackToWorking() {
        // Even a multi-word partial — "Opening Chrome for you now." would
        // be a regression. The bar bypasses the LLM's partial text and
        // shows "Working…" until streaming finishes.
        let message = ChatMessage(
            text: "Opening Chrome for you now.",
            sender: .ai,
            isStreaming: true,
            contentBlocks: [.text(id: "t1", text: "Opening Chrome for you now.")]
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Working…")
    }

    /// Tool calls are atomic events (the model decides to invoke a tool, with
    /// a fully-formed input) — these CAN drive `latestActivity` during
    /// streaming. The pill bar showing "bash — open -a 'Google Chrome'" is
    /// informative, not flickery.
    func testStreamingMessageWithToolCallReturnsToolDisplay() {
        let toolBlock = ChatContentBlock.toolCall(
            id: "tc1",
            name: "bash",
            status: .running,
            toolUseId: "tu1",
            input: ToolCallInput(summary: #"open -a "Google Chrome""#, details: nil),
            output: nil
        )
        let message = ChatMessage(
            text: "",
            sender: .ai,
            isStreaming: true,
            contentBlocks: [toolBlock]
        )
        // ChatContentBlock.displayName decorates tool names — we don't pin
        // its exact output here, just that the activity contains the tool
        // input summary AND doesn't fall back to "Working…" / partial text.
        let activity = AgentPillsManager.describeActivity(for: message)
        XCTAssertNotEqual(activity, "Working…")
        XCTAssertTrue(
            activity.contains(#"open -a "Google Chrome""#),
            "expected tool input summary in activity, got: \(activity)"
        )
    }

    /// When BOTH a tool call and a (streaming) text block are present, the
    /// streaming text must be skipped and the tool call wins. Pre-fix, the
    /// reversed iteration matched the last text block first and returned
    /// its partial content.
    func testStreamingMessageWithToolCallAndPartialTextPrefersToolCall() {
        let blocks: [ChatContentBlock] = [
            .toolCall(
                id: "tc1",
                name: "shell",
                status: .completed,
                toolUseId: "tu1",
                input: ToolCallInput(summary: "open -a Finder", details: nil),
                output: "0"
            ),
            // Trailing streaming text block — pre-fix the reversed scan hit
            // this first and returned the partial token.
            .text(id: "t1", text: "Opening Find"),
        ]
        let message = ChatMessage(
            text: "Opening Find",
            sender: .ai,
            isStreaming: true,
            contentBlocks: blocks
        )
        let activity = AgentPillsManager.describeActivity(for: message)
        // Pre-fix this returned "Opening Find" (partial text). After:
        // we get the tool description (whatever displayName produces),
        // never the partial text.
        XCTAssertFalse(activity.contains("Opening Find"), "must not surface partial streaming text; got: \(activity)")
        XCTAssertTrue(activity.contains("open -a Finder"), "expected tool input in activity; got: \(activity)")
    }

    // MARK: - Non-streaming (finalized) text is still surfaced

    /// Once the message finishes streaming, the final text takes over as
    /// `latestActivity`. This is the non-flickery completion case the
    /// fast-path button and the LLM path both rely on.
    func testFinalizedTextMessageReturnsTextPrefix() {
        let message = ChatMessage(
            text: "Created /tmp/eval/file.txt with EXECUTE_OK.",
            sender: .ai,
            isStreaming: false,
            contentBlocks: [
                .text(id: "t1", text: "Created /tmp/eval/file.txt with EXECUTE_OK.")
            ]
        )
        XCTAssertEqual(
            AgentPillsManager.describeActivity(for: message),
            "Created /tmp/eval/file.txt with EXECUTE_OK."
        )
    }

    func testFinalizedTextMessageWithoutContentBlocksFallsBackToText() {
        // Some message paths populate `text` without producing
        // contentBlocks — the fallback branch must still emit the text
        // when the message is finalized.
        let message = ChatMessage(
            text: "Done.",
            sender: .ai,
            isStreaming: false
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Done.")
    }

    /// Even on finalized messages we never show >110 chars in the bar — it's
    /// `lineLimit(1)` and 110 is plenty for the strip.
    func testFinalizedLongTextIsTruncatedToOneTenChars() {
        let body = String(repeating: "abcdefghij", count: 20) // 200 chars
        let message = ChatMessage(
            text: body,
            sender: .ai,
            isStreaming: false,
            contentBlocks: [.text(id: "t1", text: body)]
        )
        XCTAssertEqual(
            AgentPillsManager.describeActivity(for: message).count,
            110
        )
    }

    // MARK: - Empty / minimal messages

    func testEmptyMessageReturnsWorkingFallback() {
        let message = ChatMessage(
            text: "",
            sender: .ai,
            isStreaming: true
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Working…")
    }

    func testThinkingOnlyMessageReturnsWorkingFallback() {
        // `.thinking` blocks are intentionally ignored — they're internal
        // reasoning, not user-facing activity.
        let message = ChatMessage(
            text: "",
            sender: .ai,
            isStreaming: true,
            contentBlocks: [.thinking(id: "th1", text: "let me think...")]
        )
        XCTAssertEqual(AgentPillsManager.describeActivity(for: message), "Working…")
    }
}
