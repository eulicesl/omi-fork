import XCTest
@testable import Omi_Computer

/// Sprint 3 / P7 — pins intent detection and outcome decisions so a future
/// refactor doesn't quietly re-introduce the "wasted LLM call on a setup
/// miss" failure mode.
final class ExecutePreflightTests: XCTestCase {

    private func defaults(_ pairs: [String: String] = [:]) -> UserDefaults {
        // Use an isolated UserDefaults suite so test runs don't bleed into
        // each other or into the real shared defaults.
        let suite = "ExecutePreflightTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        for (k, v) in pairs { d.set(v, forKey: k) }
        return d
    }

    // MARK: - Intent detection

    func testDetectsTelegramFromQuery() {
        let intent = ExecutePreflight.detectIntent(
            query: "Send Daniel a message on Telegram",
            context: nil
        )
        XCTAssertEqual(intent, .telegram)
    }

    func testDetectsTelegramFromContext() {
        let ctx = FloatingBarNotificationContext(
            sourceTitle: "Task",
            assistantId: "task",
            sourceApp: "Telegram",
            windowTitle: nil,
            contextSummary: nil,
            currentActivity: nil,
            reasoning: nil,
            detail: nil
        )
        let intent = ExecutePreflight.detectIntent(
            query: "Send Daniel the summary",
            context: ctx
        )
        XCTAssertEqual(intent, .telegram)
    }

    func testDetectsSlack() {
        XCTAssertEqual(
            ExecutePreflight.detectIntent(
                query: "Post the metrics to #design in Slack",
                context: nil
            ),
            .slack
        )
    }

    func testDetectsGmail() {
        XCTAssertEqual(
            ExecutePreflight.detectIntent(
                query: "Send an email to the board",
                context: nil
            ),
            .gmail
        )
        XCTAssertEqual(
            ExecutePreflight.detectIntent(
                query: "Reply to the latest Gmail thread",
                context: nil
            ),
            .gmail
        )
    }

    func testNoIntentFallsThrough() {
        XCTAssertEqual(
            ExecutePreflight.detectIntent(
                query: "Summarize yesterday's standup",
                context: nil
            ),
            .none
        )
    }

    // MARK: - Outcome decisions

    func testReadyWhenTelegramRunning() {
        let outcome = ExecutePreflight.check(
            query: "Send Daniel a message on Telegram",
            context: nil,
            userDefaults: defaults(),
            isProcessRunning: { _ in true },
            launchApplication: { _ in XCTFail("should not launch when already running") }
        )
        XCTAssertEqual(outcome, .ready)
    }

    func testLaunchesTelegramWhenMissing() {
        var launched: [String] = []
        let outcome = ExecutePreflight.check(
            query: "Send Daniel a message on Telegram",
            context: nil,
            userDefaults: defaults(),
            isProcessRunning: { _ in false },
            launchApplication: { app in launched.append(app) }
        )
        XCTAssertEqual(outcome, .needs(.launchTelegram))
        XCTAssertEqual(launched, ["Telegram"])
    }

    func testNeedsPlaywrightForWebTaskWithoutToken() {
        let outcome = ExecutePreflight.check(
            query: "Reply to the latest Gmail thread",
            context: nil,
            userDefaults: defaults(),
            isProcessRunning: { _ in true },
            launchApplication: { _ in }
        )
        XCTAssertEqual(outcome, .needs(.installPlaywrightExtension))
    }

    func testReadyWhenPlaywrightTokenPresent() {
        let outcome = ExecutePreflight.check(
            query: "Reply to the latest Gmail thread",
            context: nil,
            userDefaults: defaults(["playwrightExtensionToken": "abc123"]),
            isProcessRunning: { _ in true },
            launchApplication: { _ in }
        )
        XCTAssertEqual(outcome, .ready)
    }

    func testWhitespaceOnlyPlaywrightTokenCountsAsMissing() {
        let outcome = ExecutePreflight.check(
            query: "Reply to the latest Gmail thread",
            context: nil,
            userDefaults: defaults(["playwrightExtensionToken": "   "]),
            isProcessRunning: { _ in true },
            launchApplication: { _ in }
        )
        XCTAssertEqual(outcome, .needs(.installPlaywrightExtension))
    }

    func testGenericQueryAlwaysReady() {
        let outcome = ExecutePreflight.check(
            query: "Summarize yesterday's standup",
            context: nil,
            userDefaults: defaults(),
            isProcessRunning: { _ in false },
            launchApplication: { _ in XCTFail("no app to launch for generic query") }
        )
        XCTAssertEqual(outcome, .ready)
    }
}

/// Sprint 3 / P8 — pins the verification reply parser so the model can
/// emit JSON with the usual variations (plain object, fenced object, leading
/// prose, bool-as-string, bool-as-number) and we still get a usable result.
final class VerificationParseTests: XCTestCase {

    func testParsesPlainTrue() {
        let r = ProactiveTaskExecute.parseVerification(
            #"{"verified": true, "evidence": "Last message reads 'hi'"}"#
        )
        XCTAssertEqual(
            r,
            ProactiveTaskExecute.VerificationResult(
                verified: true,
                evidence: "Last message reads 'hi'"
            )
        )
    }

    func testParsesPlainFalse() {
        let r = ProactiveTaskExecute.parseVerification(
            #"{"verified": false, "evidence": "Telegram error: chat not found"}"#
        )
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.verified, false)
        XCTAssertEqual(r?.evidence, "Telegram error: chat not found")
    }

    func testTolerantOfLeadingProse() {
        let r = ProactiveTaskExecute.parseVerification(
            "Sure, here's the verification:\n```json\n{\"verified\": true, \"evidence\": \"File at ~/Desktop/foo.md\"}\n```"
        )
        XCTAssertEqual(r?.verified, true)
        XCTAssertEqual(r?.evidence, "File at ~/Desktop/foo.md")
    }

    func testParsesBoolAsString() {
        let r = ProactiveTaskExecute.parseVerification(
            #"{"verified": "true", "evidence": "ok"}"#
        )
        XCTAssertEqual(r?.verified, true)
    }

    func testParsesBoolAsNumber() {
        let r = ProactiveTaskExecute.parseVerification(
            #"{"verified": 0, "evidence": "nothing happened"}"#
        )
        XCTAssertEqual(r?.verified, false)
    }

    func testReturnsNilWhenVerifiedFieldMissing() {
        let r = ProactiveTaskExecute.parseVerification(
            #"{"evidence": "I think it worked"}"#
        )
        XCTAssertNil(r)
    }

    func testReturnsNilOnGarbage() {
        XCTAssertNil(ProactiveTaskExecute.parseVerification("yes it worked great"))
        XCTAssertNil(ProactiveTaskExecute.parseVerification(""))
    }

    func testTruncatesLongEvidence() {
        let huge = String(repeating: "a", count: 500)
        let r = ProactiveTaskExecute.parseVerification(
            #"{"verified": true, "evidence": "\#(huge)"}"#
        )
        XCTAssertEqual(r?.verified, true)
        XCTAssertLessThanOrEqual(r?.evidence.count ?? 0, 200)
    }
}
