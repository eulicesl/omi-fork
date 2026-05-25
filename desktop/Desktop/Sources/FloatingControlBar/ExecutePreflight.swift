import Foundation

/// Sprint 3 / P7 — fast host-side checks before we spend an LLM call on a
/// task that's destined to fail in setup.
///
/// Today's failure mode: a "send via Slack" Execute click without the Slack
/// desktop client signed in burns a 20-second LLM tool-use round trip before
/// the user sees "couldn't sign in to Slack." This struct moves that check
/// to the *click site* — we know the task wording up front, so we can detect
/// the channel and surface the setup UI before the agent starts.
///
/// Conservative by design: when in doubt, return `.ready` and let the agent
/// try. A false `.needs(…)` blocks legitimate work, a missed `.needs(…)`
/// merely degrades to today's wasted-LLM-call behavior.
enum ExecutePreflight {

    /// Concrete requirement the user has to satisfy before the agent can
    /// usefully run. The Execute click site renders a tailored setup sheet
    /// per requirement instead of letting the agent fail mid-turn.
    enum Requirement: Equatable {
        case launchTelegram
        case signInSlack
        case installPlaywrightExtension
        case signInGmail
    }

    enum Outcome: Equatable {
        case ready
        case needs(Requirement)
    }

    /// Quick check at click time. Side-effect-free except for the
    /// `open -a Telegram` nudge: if the task mentions Telegram and the app
    /// isn't running, we ask the system to bring it up before we ask the
    /// agent to drive it. Returns `.ready` once the launch nudge has been
    /// sent; the agent's first tool call still verifies it landed.
    ///
    /// The check is intentionally tolerant — if we can't tell, we say
    /// `.ready` rather than block a legitimate run.
    static func check(
        query: String,
        context: FloatingBarNotificationContext?,
        userDefaults: UserDefaults = .standard,
        isProcessRunning: (String) -> Bool = ExecutePreflight.defaultProcessProbe,
        launchApplication: (String) -> Void = ExecutePreflight.defaultLauncher
    ) -> Outcome {
        let intent = detectIntent(query: query, context: context)

        switch intent {
        case .telegram:
            if !isProcessRunning("Telegram") {
                // Best effort: kick off the launch. The agent should still
                // succeed once it comes up; if not, surfacing the dialog is
                // better than a silent fail.
                launchApplication("Telegram")
                return .needs(.launchTelegram)
            }
            return .ready

        case .slack:
            if !isProcessRunning("Slack") {
                return .needs(.signInSlack)
            }
            return .ready

        case .webRequired:
            let token = userDefaults
                .string(forKey: "playwrightExtensionToken")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (token ?? "").isEmpty {
                return .needs(.installPlaywrightExtension)
            }
            return .ready

        case .gmail:
            let token = userDefaults
                .string(forKey: "playwrightExtensionToken")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (token ?? "").isEmpty {
                return .needs(.installPlaywrightExtension)
            }
            // Gmail also needs the user signed in — the extension cookie is
            // the only thing we can cheaply check. The agent will surface
            // the sign-in prompt itself if the cookie is stale.
            return .ready

        case .none:
            return .ready
        }
    }

    // MARK: - Intent detection

    enum Intent: Equatable {
        case telegram
        case slack
        case gmail
        /// Generic web-required task (post on X, schedule via web Calendar,
        /// etc.) — Playwright extension is required, but we don't know the
        /// specific channel.
        case webRequired
        case none
    }

    static func detectIntent(
        query: String,
        context: FloatingBarNotificationContext?
    ) -> Intent {
        let lower = query.lowercased()
        let sourceApp = context?.sourceApp?.lowercased() ?? ""

        if lower.contains("telegram") || sourceApp.contains("telegram") {
            return .telegram
        }
        if lower.contains("slack") || sourceApp.contains("slack") {
            return .slack
        }
        if lower.contains("gmail") || lower.contains("email") || sourceApp.contains("mail") {
            return .gmail
        }
        if lower.contains("twitter") || lower.contains(" x ") || lower.contains("post on x") {
            return .webRequired
        }
        return .none
    }

    // MARK: - Default probes

    /// Best-effort process check via `pgrep`. Falls back to "running" on any
    /// failure so we don't block legitimate runs because of a probe glitch.
    static let defaultProcessProbe: (String) -> Bool = { name in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-xq", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return true
        }
    }

    /// `open -a <app>` nudge. No-op on failure.
    static let defaultLauncher: (String) -> Void = { app in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", app]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
