import Combine
import Foundation
import SwiftUI

/// A running or finished background "agent" launched from the Ask Omi floating
/// bar. Each pill owns its own `ChatProvider` so multiple agents can execute in
/// parallel without sharing message state.
@MainActor
final class AgentPill: ObservableObject, Identifiable {
    enum Status: Equatable {
        case queued
        case starting
        case running
        case done
        case failed(String)

        var displayLabel: String {
            switch self {
            case .queued: return "Queued"
            case .starting, .running: return "Running"
            case .done: return "Done"
            case .failed: return "Failed"
            }
        }
    }

    /// Whether the pill's query expects the agent to *take an action* on the
    /// user's apps (Send / Reply / Create / Schedule / …) vs. produce a
    /// research-y reply. Used by `ExecuteVerificationGate` so we only demote
    /// pills to `.failed("no tool called")` when a tool *was* expected.
    enum ActionClass {
        case actionable
        case research
    }

    let id = UUID()
    let query: String
    let createdAt: Date
    let model: String
    /// Whether this pill was spawned from a proactive task notification's
    /// Execute button. Controls the verification gate and the retry loop —
    /// both are Execute-mode opt-ins so user-driven "spawn 3 agents" pills
    /// keep their existing single-shot, no-gate behavior.
    let isExecuteMode: Bool
    /// Derived from the query at spawn time so the gate can run without
    /// re-parsing the prompt.
    let actionClass: ActionClass
    /// Set by Sprint 3 / P8 after the verification turn returns. nil when
    /// the pill is research-class (no verification fired) or when the
    /// verification turn was skipped because the local gate already failed.
    @Published var verification: ProactiveTaskExecute.VerificationResult?

    @Published var title: String
    @Published var status: Status = .queued
    @Published var latestActivity: String = "Queued…"
    @Published var transcript: [String] = []
    @Published var aiMessage: ChatMessage?
    @Published var completedAt: Date?
    @Published var suggestedFollowUps: [String] = []
    /// Number of attempts so far (1 on first run, 2 on a single retry). Used
    /// by the pill UI to surface "Retrying… (2/2)" and by analytics.
    @Published var attemptCount: Int = 0

    /// Convenience: how long the agent has been running (or ran).
    var elapsed: TimeInterval {
        (completedAt ?? Date()).timeIntervalSince(createdAt)
    }

    init(query: String, model: String, isExecuteMode: Bool = false) {
        self.query = query
        self.model = model
        self.isExecuteMode = isExecuteMode
        self.actionClass = ExecuteVerificationGate.classify(query: query)
        self.title = AgentPill.deriveTitle(from: query)
        self.createdAt = Date()
    }

    /// Pull a short uppercase title out of the query for the pill popover header.
    /// "open google.com and find vegan ramen" → "OPEN GOOGLE.COM"
    private static func deriveTitle(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed
            .split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            .prefix(3)
            .map(String.init)
        let joined = words.joined(separator: " ").uppercased()
        if joined.count > 32 {
            return String(joined.prefix(32)) + "…"
        }
        return joined.isEmpty ? "AGENT" : joined
    }
}

/// Singleton that owns the running `AgentPill`s. Spawning a pill creates a new
/// `ChatProvider` and observes its message stream until the agent finishes.
@MainActor
final class AgentPillsManager: ObservableObject {
    static let shared = AgentPillsManager()

    @Published private(set) var pills: [AgentPill] = []
    @Published var hoveredPillID: UUID?
    @Published var pinnedPillID: UUID?

    /// Configurable soft cap so the row never grows past a reasonable width.
    private let maxPills: Int = 8

    /// One ChatProvider (and therefore one ACP node subprocess) per pill so
    /// pills can truly run in parallel — each provider has its own bridge,
    /// `isSending` flag, and interrupt scope. Bridges are heavy to boot, so we
    /// stagger their startup via `bootChain` to avoid the race we saw the first
    /// time around. After boot completes, every pill's `sendMessage` runs in
    /// parallel with the others.
    private var providersByPill: [UUID: ChatProvider] = [:]
    private var streamsByPill: [UUID: AnyCancellable] = [:]
    private var messageCountByPill: [UUID: Int] = [:]
    private var bootChain: Task<Void, Never> = Task {}

    /// Notification IDs we've already spawned an Execute pill for in the last
    /// `executeDedupTTL` seconds. Prevents a double-click on the Execute
    /// button (or two clicks while the agent is warming up) from launching
    /// two parallel pills racing to send the same message / create the same
    /// event. Cleared on a delay so a long-running task can be re-triggered
    /// later if the user genuinely wants to retry.
    private var recentExecuteNotificationIds: Set<UUID> = []
    private let executeDedupTTL: TimeInterval = 60

    private init() {}

    /// Routing decision for an Ask Omi message — does it stay inline in the
    /// floating bar, or get hoisted into a background agent pill?
    enum Route: String { case chat, agent }

    /// Combined router result. Title/ack are pre-computed alongside the route
    /// so we don't need a second Haiku call when the answer is "agent".
    struct RouterDecision {
        let route: Route
        let title: String?
        let ack: String?
    }

    struct AutomationSnapshot: Codable {
        let pillId: String
        let title: String
        let status: String
        let error: String?
        let latestActivity: String
        let attemptCount: Int
        let actionClass: String
        let isExecuteMode: Bool
        let invokedToolNames: [String]
        let verificationVerified: Bool?
        let verificationEvidence: String?
        let completedAt: String?
        let aiText: String?
    }

    /// Ask Claude Haiku whether the message is a quick info question (→ chat)
    /// or a background task (→ agent). Falls back to `.chat` on error/timeout
    /// so we never accidentally hijack a question into a long-running pill.
    /// ~300-500ms via the desktop-backend's OpenAI-compatible proxy.
    static func classify(_ query: String) async -> RouterDecision {
        guard let result = await runRouterCall(for: query) else {
            return RouterDecision(route: .chat, title: nil, ack: nil)
        }
        return result
    }

    private static func runRouterCall(for query: String) async -> RouterDecision? {
        let baseURL = await APIClient.shared.rustBackendURL
        guard !baseURL.isEmpty else {
            log("AgentPill: router skipped — rustBackendURL empty, defaulting to chat")
            return nil
        }
        let normalized = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let url = URL(string: normalized + "v2/chat/completions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        do {
            let headers = try await APIClient.shared.buildHeaders(requireAuth: true)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        } catch {
            log("AgentPill: router skipped — auth header unavailable (\(error.localizedDescription))")
            return nil
        }

        let prompt = """
        The user just sent this message in the Omi floating bar:

        "\(query)"

        Decide whether to (a) answer it inline in the chat bar, or (b) spawn a background agent that will do work on the user's computer/apps/browser.

        Reply with ONLY a single-line JSON object, no prose, no markdown:
        {"route":"chat"|"agent","title":"<3-5 word imperative title in Title Case, no trailing punctuation>","ack":"<one short spoken acknowledgement, max 7 words, friendly tone>"}

        Use "agent" ONLY when the request requires the assistant to take real actions on the user's computer/browser/apps that will plausibly take more than ~10 seconds — building/coding something, sending/posting a message, editing or creating files, multi-step browser navigation, generating a long document.
        Use "chat" for everything else: questions, lookups (even if the user uses words like "search"/"find"/"look up"), definitions, single facts, explanations, short summaries, opinions, conversation. When in doubt, choose "chat".
        """

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 120,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("AgentPill: router failed — no HTTP response, defaulting to chat")
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                log("AgentPill: router HTTP \(http.statusCode) — \(bodyText), defaulting to chat")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text = message["content"] as? String
            else {
                log("AgentPill: router response shape unexpected, defaulting to chat")
                return nil
            }
            // Haiku occasionally ignores the "no markdown" instruction and
            // wraps the JSON in ```json ... ``` fences, or emits leading
            // prose. Extract the first balanced {...} object instead of
            // trusting the whole response to be raw JSON.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonBody: String
            if let firstBrace = trimmed.firstIndex(of: "{"),
                let lastBrace = trimmed.lastIndex(of: "}"),
                firstBrace < lastBrace
            {
                jsonBody = String(trimmed[firstBrace...lastBrace])
            } else {
                jsonBody = trimmed
            }
            guard let payloadData = jsonBody.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                let routeStr = (payload["route"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            else {
                log("AgentPill: router JSON parse failed — raw: \(String(trimmed.prefix(200))), defaulting to chat")
                return nil
            }
            let route = Route(rawValue: routeStr) ?? .chat
            let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ack = (payload["ack"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            log("AgentPill: router decided route=\(route.rawValue) title=\"\(title ?? "")\"")
            return RouterDecision(
                route: route,
                title: (title?.isEmpty == false) ? String(title!.prefix(40)) : nil,
                ack: (ack?.isEmpty == false) ? String(ack!.prefix(120)) : nil
            )
        } catch {
            log("AgentPill: router threw — \(error.localizedDescription), defaulting to chat")
            return nil
        }
    }

    /// Parse phrases like "spawn 3 agents", "5 tasks", "two agents working in
    /// parallel" out of a user query. Returns 1 if no count is mentioned.
    /// Handles "3 test agents" — words between the number and the noun are
    /// allowed (up to 5 tokens) so demo phrasing doesn't fall through.
    static func parseAgentCount(from text: String) -> Int {
        let lower = text.lowercased()
        let nounGroup = "(?:agents?|tasks?|pills?|things?)"
        // Numeric: "3 agents", "spawn 5 in parallel", "3 test agents",
        // "spawn 3 of these", but NOT "in 30 seconds".
        // Allow up to ~5 short words between the number and the noun.
        let numericPattern = #"\b(\d+)(?:\s+\S+){0,5}\s+\#(nounGroup)\b"#
        if let regex = try? NSRegularExpression(pattern: numericPattern),
            let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: lower),
            let n = Int(lower[range]),
            n > 0
        {
            return min(n, 8)
        }
        // Word form: "two agents", "three tasks", "five test agents"
        let wordToNumber: [String: Int] = [
            "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        ]
        let wordPattern = #"\b(two|three|four|five|six|seven|eight)(?:\s+\S+){0,5}\s+\#(nounGroup)\b"#
        if let regex = try? NSRegularExpression(pattern: wordPattern),
            let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: lower),
            let n = wordToNumber[String(lower[range])]
        {
            return min(n, 8)
        }
        return 1
    }

    /// Spawn one or more pills for a user query. If the query says "spawn 3
    /// agents" we create 3 pills (each runs the same task on the shared
    /// queue). Returns the first pill so callers can inspect it.
    @discardableResult
    func spawnFromUserQuery(
        _ query: String,
        model: String,
        fromVoice: Bool = false,
        preFetchedTitle: String? = nil,
        preFetchedAck: String? = nil
    ) -> AgentPill {
        let count = AgentPillsManager.parseAgentCount(from: query)
        if count <= 1 {
            return spawn(
                query: query,
                model: model,
                fromVoice: fromVoice,
                preFetchedTitle: preFetchedTitle,
                preFetchedAck: preFetchedAck
            )
        }
        var first: AgentPill?
        for i in 1...count {
            let labelled = "[\(i)/\(count)] \(query)"
            // Only the first pill speaks the acknowledgement when N > 1,
            // otherwise we'd hear N overlapping voices. Only the first pill
            // gets the pre-fetched title/ack — the others fall back to their
            // own title generation since their query text differs (the
            // [i/N] prefix changes the model's output).
            let pill = spawn(
                query: labelled,
                model: model,
                fromVoice: fromVoice && first == nil,
                preFetchedTitle: first == nil ? preFetchedTitle : nil,
                preFetchedAck: first == nil ? preFetchedAck : nil
            )
            if first == nil { first = pill }
        }
        return first ?? spawn(query: query, model: model, fromVoice: fromVoice)
    }

    /// Spawn an Execute pill for a proactive task notification. Dedupes by
    /// `notificationId` so a double-click (or two clicks while the bridge is
    /// warming up) doesn't fire two parallel pills against the same task.
    /// Returns nil when a recent pill already covers this notification.
    ///
    /// Execute pills opt in to (a) the verification gate (`ExecuteVerificationGate`),
    /// (b) a single transparent retry on transient bridge errors and gate
    /// misses. Both are intentionally Execute-mode-only — user-driven
    /// "spawn 3 agents" pills keep their single-shot semantics so a
    /// transient bridge blip doesn't silently double the LLM cost.
    @discardableResult
    func spawnForNotification(
        notificationId: UUID,
        query: String,
        model: String,
        systemPromptSuffix: String? = nil,
        systemPromptPrefix: String? = nil
    ) -> AgentPill? {
        if recentExecuteNotificationIds.contains(notificationId) {
            log("AgentPillsManager: ignoring duplicate Execute click for notification \(notificationId)")
            return nil
        }
        recentExecuteNotificationIds.insert(notificationId)
        let ttl = executeDedupTTL
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak self] in
            self?.recentExecuteNotificationIds.remove(notificationId)
        }

        return spawn(
            query: query,
            model: model,
            systemPromptSuffix: systemPromptSuffix,
            systemPromptPrefix: systemPromptPrefix,
            isExecuteMode: true
        )
    }

    /// Direct-action variant of `spawnForNotification`: runs a deterministic
    /// host-side action (e.g. `open -a "Google Chrome"`) without an LLM turn,
    /// then surfaces a terminal pill describing what happened. Shares the
    /// same dedup window as `spawnForNotification` so a double-click can't
    /// launch Chrome twice — and so the second click doesn't quietly fall
    /// back to the LLM path either.
    ///
    /// On a non-zero exit from `/usr/bin/open` the pill lands as `.failed`,
    /// not `.done`, so the UI / status snapshot don't claim success for a
    /// launch that didn't happen.
    @discardableResult
    func spawnDirectActionForNotification(
        notificationId: UUID,
        query: String,
        model: String,
        title: String,
        action: ProactiveTaskExecute.DirectDesktopAction
    ) async -> AgentPill? {
        if recentExecuteNotificationIds.contains(notificationId) {
            log("AgentPillsManager: ignoring duplicate Execute click for notification \(notificationId)")
            return nil
        }
        recentExecuteNotificationIds.insert(notificationId)
        let ttl = executeDedupTTL
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak self] in
            self?.recentExecuteNotificationIds.remove(notificationId)
        }

        let activity: String
        let status: AgentPill.Status
        do {
            activity = try await ProactiveTaskExecute.perform(action)
            status = .done
        } catch {
            let reason = error.localizedDescription
            activity = "Failed: \(reason)"
            status = .failed(reason)
        }
        return spawnCompletedDirectAction(
            query: query,
            model: model,
            title: title,
            activity: activity,
            status: status
        )
    }

    /// Create a terminal pill for deterministic host-side actions that have
    /// already run. No ChatProvider, no agent session — we just want a
    /// finished pill (`.done` on success, `.failed` on a non-zero exit) so
    /// the user sees a record of what happened alongside their other Execute
    /// history. `status` defaults to `.done` to keep the success-path call
    /// sites short; callers that ran a process pass through the actual
    /// outcome.
    @discardableResult
    func spawnCompletedDirectAction(
        query: String,
        model: String,
        title: String,
        activity: String,
        status: AgentPill.Status = .done
    ) -> AgentPill {
        let pill = AgentPill(query: query, model: model, isExecuteMode: true)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            pill.title = String(trimmedTitle.prefix(40))
        }

        if pills.count >= maxPills {
            if let idx = pills.firstIndex(where: { isFinished($0.status) }) {
                cleanup(pillID: pills[idx].id)
            } else {
                cleanup(pillID: pills[0].id)
            }
        }

        pill.status = status
        pill.latestActivity = ProactiveTaskExecute.completionActivityText(from: activity)
        pill.completedAt = Date()
        pill.attemptCount = 1
        pill.suggestedFollowUps = AgentPillsManager.deriveFollowUps(for: pill)
        pills.append(pill)
        return pill
    }

    /// Spawn a new agent pill. Each pill gets its own ChatProvider so the
    /// pills truly run in parallel. Bridge boots are staggered through
    /// `bootChain` so we never race ACP startup; once a pill's bridge is
    /// warmed it sends concurrently with everything else.
    ///
    /// `systemPromptPrefix` defaults to the floating-bar "1-2 sentences, no
    /// follow-ups" prefix because most pills are spawned from user voice / text
    /// queries that want the inline-bar tone. Execute pills override this with
    /// `nil` — see `spawnForNotification` — because the floating-bar concise
    /// rules conflict with the Execute "use as many tool calls as you need"
    /// suffix, and prepended rules tend to win over appended ones in practice.
    @discardableResult
    func spawn(
        query: String,
        model: String,
        fromVoice: Bool = false,
        preFetchedTitle: String? = nil,
        preFetchedAck: String? = nil,
        systemPromptSuffix: String? = nil,
        systemPromptPrefix: String? = ChatProvider.floatingBarSystemPromptPrefix,
        isExecuteMode: Bool = false
    ) -> AgentPill {
        let pill = AgentPill(query: query, model: model, isExecuteMode: isExecuteMode)
        if let preFetchedTitle, !preFetchedTitle.isEmpty {
            pill.title = preFetchedTitle
        }

        // Trim if we're at the cap — drop the oldest finished pill first.
        if pills.count >= maxPills {
            if let idx = pills.firstIndex(where: { isFinished($0.status) }) {
                cleanup(pillID: pills[idx].id)
            } else {
                cleanup(pillID: pills[0].id)
            }
        }

        pills.append(pill)

        let provider = ChatProvider()
        if let floating = FloatingControlBarManager.shared.sharedFloatingProvider {
            provider.workingDirectory = floating.workingDirectory
            provider.modelOverride = floating.modelOverride
        }
        providersByPill[pill.id] = provider

        let messageCountBefore = provider.messages.count
        messageCountByPill[pill.id] = messageCountBefore
        streamsByPill[pill.id] = provider.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak pill] messages in
                guard let self, let pill else { return }
                self.handle(messages: messages, since: messageCountBefore, for: pill)
            }

        // Stagger bridge boots: chain this pill's warmup after the previous
        // pill's. Once warmed, the actual sendMessage runs in parallel with
        // every other warmed pill.
        let previousBoot = bootChain
        let myBoot = Task { [weak provider] in
            await previousBoot.value
            await provider?.warmupBridge()
        }
        bootChain = myBoot

        pill.status = .starting
        if let preFetchedAck, !preFetchedAck.isEmpty {
            pill.latestActivity = preFetchedAck
        } else {
            pill.latestActivity = "Warming up…"
        }

        // For voice queries, speak the pre-fetched ack from the router (or a
        // random instant ack) BEFORE waiting for the bridge so the user
        // always hears confirmation that we heard them.
        if fromVoice {
            let phrase = (preFetchedAck?.isEmpty == false) ? preFetchedAck! : AgentPillsManager.randomAck()
            FloatingBarVoicePlaybackService.shared.speakOneShot(phrase)
        }

        // If the router already returned a title we don't need a second
        // Haiku call for title generation. Otherwise kick one off in the
        // background to upgrade the heuristic title.
        if preFetchedTitle == nil {
            Task { [weak pill] in
                guard let pill else { return }
                guard let result = await AgentPillsManager.generateTitleAndAck(for: pill.query) else { return }
                await MainActor.run {
                    pill.title = result.title
                    if pill.latestActivity == "Warming up…" || pill.latestActivity == "Starting…" {
                        pill.latestActivity = result.ack
                    }
                }
            }
        }

        Task { [weak self, weak pill, weak provider] in
            await myBoot.value
            guard let self, let pill, let provider else { return }
            // Bridge is up; flip to running and fire the prompt. Concurrent
            // with any other pill that's already past this point.
            pill.status = .running

            // Sprint 2 / P3 — single transparent retry for Execute pills.
            // maxAttempts = 1 for everything else (the user-driven "spawn N
            // agents" path keeps single-shot semantics so a transient bridge
            // blip doesn't silently double LLM cost).
            let maxAttempts = pill.isExecuteMode ? 2 : 1
            for attempt in 1...maxAttempts {
                pill.attemptCount = attempt
                if attempt > 1 {
                    pill.latestActivity = "Retrying (\(attempt)/\(maxAttempts))…"
                    pill.transcript.append("Retrying (\(attempt)/\(maxAttempts))")
                    log("AgentPillsManager: retry \(attempt)/\(maxAttempts) for pill \(pill.id)")
                }
                // Fresh sessionKey on retry so we don't reuse a broken
                // session. Format must match `pill.id` discoverability —
                // append the attempt only when > 1 so attempt 1 keeps the
                // original key for any debug log correlation.
                let sessionKey = attempt == 1
                    ? "agent-\(pill.id.uuidString)"
                    : "agent-\(pill.id.uuidString)-r\(attempt)"
                await provider.sendMessage(
                    pill.query,
                    model: pill.model,
                    systemPromptSuffix: systemPromptSuffix,
                    systemPromptPrefix: systemPromptPrefix,
                    sessionKey: sessionKey
                )
                let outcome = await self.evaluateAttempt(
                    pill: pill,
                    provider: provider,
                    sessionKey: sessionKey
                )
                if outcome == .terminal || attempt == maxAttempts {
                    break
                }
                // Clear provider state between attempts so a stale errorMessage
                // from the failed attempt doesn't bleed into the next run's
                // `complete()` evaluation. The placeholder AI message inside
                // ChatProvider is already finalized at this point.
                provider.errorMessage = nil
            }
            self.complete(pill: pill, provider: provider)
        }

        return pill
    }

    /// Verdict on a single send attempt — does the retry loop continue?
    enum AttemptOutcome { case terminal, retry }

    /// Decide whether the attempt that just finished is good enough to ship
    /// (`.terminal`) or should be retried (`.retry`). Non-Execute pills are
    /// always terminal — they're single-shot by contract.
    ///
    /// For actionable Execute pills that pass the local tool-usage gate, we
    /// run Sprint 3 / P8's programmatic verification turn here so a
    /// negative verdict triggers a retry rather than a misleading `.done`.
    private func evaluateAttempt(
        pill: AgentPill,
        provider: ChatProvider,
        sessionKey: String
    ) async -> AttemptOutcome {
        guard pill.isExecuteMode else { return .terminal }

        if let errText = provider.errorMessage, !errText.isEmpty {
            // Retry only on transient transport errors. User stops + model-
            // reported impossibility are terminal.
            return Self.isRetryableErrorText(errText) ? .retry : .terminal
        }

        let invoked = Self.invokedToolNames(from: pill.aiMessage)
        let gate = ExecuteVerificationGate.evaluate(
            actionClass: pill.actionClass,
            invokedToolNames: invoked
        )
        switch gate {
        case .unverified:
            log("AgentPillsManager: gate flagged pill \(pill.id) as unverified — will retry")
            return .retry
        case .verified:
            // Local gate passed. For actionable pills, fire the
            // programmatic verification turn on the same warm session for
            // proof-quality evidence. Research pills skip — there's nothing
            // to verify.
            if pill.actionClass == .research {
                return .terminal
            }
            let result = await Self.runVerificationTurn(
                pill: pill,
                provider: provider,
                sessionKey: sessionKey
            )
            pill.verification = result
            if let result {
                if result.verified {
                    return .terminal
                } else {
                    log("AgentPillsManager: verification turn failed for pill \(pill.id) — evidence: \(result.evidence)")
                    return .retry
                }
            }
            // Verification turn errored / unparseable. Don't infinite-loop —
            // accept the local gate's verdict. Logged so we can tell when
            // this happens in production.
            log("AgentPillsManager: verification turn unparseable for pill \(pill.id) — accepting local-gate verdict")
            return .terminal
        }
    }

    /// Run Sprint 3 / P8's verification follow-up. Reuses the pill's warm
    /// provider/session so the model already has the conversation history
    /// in cache. Returns nil when the turn errors or the reply doesn't
    /// parse as `{verified, evidence}` JSON.
    private static func runVerificationTurn(
        pill: AgentPill,
        provider: ChatProvider,
        sessionKey: String
    ) async -> ProactiveTaskExecute.VerificationResult? {
        // Snapshot the AI message before the verification turn appends.
        // We never want to display the verification prompt itself as a
        // separate bubble — only its parsed evidence.
        let messageCountBefore = provider.messages.count
        pill.latestActivity = "Verifying…"

        await provider.sendMessage(
            ProactiveTaskExecute.verificationPrompt,
            model: pill.model,
            sessionKey: sessionKey
        )

        guard provider.errorMessage?.isEmpty != false else {
            return nil
        }
        // The newest AI message after our send is the verification reply.
        let newer = provider.messages.dropFirst(messageCountBefore)
        guard let reply = newer.last(where: { $0.sender == .ai }) else {
            return nil
        }
        return ProactiveTaskExecute.parseVerification(reply.text)
    }

    /// Walk a finished AI message's content blocks and pull out every
    /// `.toolCall` name. Used by the verification gate.
    static func invokedToolNames(from message: ChatMessage?) -> [String] {
        guard let message else { return [] }
        var names: [String] = []
        for block in message.contentBlocks {
            if case .toolCall(_, let name, _, _, _, _) = block {
                names.append(name)
            }
        }
        return names
    }

    /// Heuristic for whether a bridge / network / OOM error is worth a retry.
    /// Matches on the user-visible error text since BridgeError isn't directly
    /// observable from the pill side.
    static func isRetryableErrorText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let retryableMarkers = [
            "took too long",         // 180s watchdog
            "process exited",        // BridgeError.processExited
            "out of memory",         // BridgeError.outOfMemory
            "ai not available",      // bridge failed to start
            "ai not running",
            "timeout",
            "connection",
            "stalled",               // Sprint 3 / P9 will produce this
        ]
        let nonRetryableMarkers = [
            "limit reached", "upgrade",   // billing / usage cap
            "stopped",                    // user pressed stop
        ]
        if nonRetryableMarkers.contains(where: { lower.contains($0) }) { return false }
        return retryableMarkers.contains(where: { lower.contains($0) })
    }

    /// Force-dismiss a pill.
    func dismiss(pillID: UUID) {
        cleanup(pillID: pillID)
        if hoveredPillID == pillID { hoveredPillID = nil }
        if pinnedPillID == pillID { pinnedPillID = nil }
    }

    func automationSnapshot(pillID: UUID) -> AutomationSnapshot? {
        guard let pill = pills.first(where: { $0.id == pillID }) else { return nil }
        let status: String
        let error: String?
        switch pill.status {
        case .queued:
            status = "queued"
            error = nil
        case .starting:
            status = "starting"
            error = nil
        case .running:
            status = "running"
            error = nil
        case .done:
            status = "done"
            error = nil
        case .failed(let reason):
            status = "failed"
            error = reason
        }

        let formatter = ISO8601DateFormatter()
        return AutomationSnapshot(
            pillId: pill.id.uuidString,
            title: pill.title,
            status: status,
            error: error,
            latestActivity: pill.latestActivity,
            attemptCount: pill.attemptCount,
            actionClass: pill.actionClass == .actionable ? "actionable" : "research",
            isExecuteMode: pill.isExecuteMode,
            invokedToolNames: Self.invokedToolNames(from: pill.aiMessage),
            verificationVerified: pill.verification?.verified,
            verificationEvidence: pill.verification?.evidence,
            completedAt: pill.completedAt.map { formatter.string(from: $0) },
            aiText: pill.aiMessage?.text
        )
    }

    private func cleanup(pillID: UUID) {
        streamsByPill[pillID]?.cancel()
        streamsByPill[pillID] = nil
        providersByPill[pillID] = nil
        messageCountByPill[pillID] = nil
        pills.removeAll { $0.id == pillID }
    }

    /// Remove all completed (done or failed) pills.
    func clearCompleted() {
        pills.removeAll { isFinished($0.status) }
    }

    private func isFinished(_ status: AgentPill.Status) -> Bool {
        switch status {
        case .done, .failed: return true
        default: return false
        }
    }

    private func handle(messages: [ChatMessage], since: Int, for pill: AgentPill) {
        guard messages.count > since else { return }
        let recent = Array(messages.suffix(from: since))
        guard let aiMessage = recent.last(where: { $0.sender == .ai }) else { return }
        pill.aiMessage = aiMessage

        if pill.status == .starting {
            pill.status = .running
        }

        let activity = describeActivity(for: aiMessage)
        if !activity.isEmpty && activity != pill.latestActivity {
            pill.latestActivity = activity
            pill.transcript.append(activity)
        }
    }

    private func describeActivity(for message: ChatMessage) -> String {
        for block in message.contentBlocks.reversed() {
            switch block {
            case .toolCall(_, let name, _, _, let input, _):
                let display = ChatContentBlock.displayName(for: name)
                if let input, !input.summary.isEmpty {
                    return "\(display) — \(input.summary)"
                }
                return display
            case .text(_, let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return String(trimmed.prefix(110))
                }
            case .thinking, .discoveryCard:
                continue
            }
        }
        let trimmedFallback = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallback.isEmpty {
            return String(trimmedFallback.prefix(110))
        }
        return "Working…"
    }

    private func complete(pill: AgentPill, provider: ChatProvider) {
        if let errorText = provider.errorMessage, !errorText.isEmpty {
            pill.status = .failed(errorText)
            pill.latestActivity = errorText
        } else if pill.isExecuteMode {
            // Sprint 2 / P2 — verification gate. Demote to `.failed` if the
            // pill is actionable but no write/send/script tool fired. We
            // already retried once in the spawn loop, so reaching here means
            // every attempt was unverified.
            let invoked = Self.invokedToolNames(from: pill.aiMessage)
            let gate = ExecuteVerificationGate.evaluate(
                actionClass: pill.actionClass,
                invokedToolNames: invoked
            )
            switch gate {
            case .verified:
                // Sprint 3 / P8 — if the verification turn ran and produced
                // a negative verdict, prefer its message over the model's
                // free-text. We've already exhausted retries by the time
                // we reach complete(), so this is the terminal outcome.
                if let v = pill.verification, !v.verified {
                    let reason = "Could not verify: \(v.evidence.isEmpty ? "no evidence" : v.evidence)"
                    log("AgentPillsManager: pill \(pill.id) failed verification turn after \(pill.attemptCount) attempt(s)")
                    pill.status = .failed(reason)
                    pill.latestActivity = reason
                    break
                }
                pill.status = .done
                if let v = pill.verification, v.verified, !v.evidence.isEmpty {
                    // Surface the proof to the user instead of the model's
                    // free-text claim — "Sent — last message reads 'Hey…'"
                    pill.latestActivity = "Done — \(v.evidence)"
                } else if let last = pill.aiMessage, !last.text.isEmpty {
                    let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    pill.latestActivity = String(trimmed.prefix(140))
                } else {
                    pill.latestActivity = "Done"
                }
            case .unverified(let reason):
                log("AgentPillsManager: pill \(pill.id) failed verification gate after \(pill.attemptCount) attempt(s) — \(reason)")
                pill.status = .failed(reason)
                pill.latestActivity = reason
            }
        } else {
            pill.status = .done
            if let last = pill.aiMessage, !last.text.isEmpty {
                let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                pill.latestActivity = String(trimmed.prefix(140))
            } else {
                pill.latestActivity = "Done"
            }
        }
        pill.completedAt = Date()
        pill.suggestedFollowUps = AgentPillsManager.deriveFollowUps(for: pill)
        // Tear down this pill's stream so we stop holding the provider — the
        // node bridge process will deinit when no Swift references remain.
        streamsByPill[pill.id]?.cancel()
        streamsByPill[pill.id] = nil
        providersByPill[pill.id] = nil
        messageCountByPill[pill.id] = nil
    }

    /// Tiny heuristic to suggest 1–2 follow-ups based on the original query.
    /// "Open chat" is intentionally omitted — the popover already has a
    /// dedicated "Open in chat" button, so adding it as a chip would duplicate.
    private static func deriveFollowUps(for pill: AgentPill) -> [String] {
        let lower = pill.query.lowercased()
        if lower.contains("email") || lower.contains("reply") {
            return ["Open thread", "Check for replies"]
        }
        if lower.contains("search") || lower.contains("find") || lower.contains("look") {
            return ["Open results", "Refine search"]
        }
        if lower.contains("schedule") || lower.contains("book") || lower.contains("calendar") {
            return ["Open calendar", "Add reminder"]
        }
        return ["Run again"]
    }

    /// Ask Claude Haiku for a short title (3–5 words, present participle) and
    /// a one-sentence acknowledgement we can speak aloud. Returns nil if the
    /// API key isn't available or the call fails — the caller keeps the
    /// existing heuristic title in that case.
    /// Short, instant acknowledgements spoken the moment a voice query spawns
    /// a pill. Random pick so consecutive PTT queries don't sound identical.
    private static let instantAcks: [String] = [
        "On it.",
        "Got it.",
        "Sure thing.",
        "Working on it.",
        "Alright, doing that now.",
        "Let me get that started.",
        "Okay, on it.",
    ]

    fileprivate static func randomAck() -> String {
        instantAcks.randomElement() ?? "On it."
    }

    fileprivate static func generateTitleAndAck(for query: String) async -> (title: String, ack: String)? {
        // Route through the desktop-backend's OpenAI-compatible proxy at
        // /v2/chat/completions instead of hitting api.anthropic.com directly.
        // This way we don't need a BYOK key (no partial-BYOK 403 risk), and
        // the request goes through the user's existing Firebase auth + plan.
        let baseURL = await APIClient.shared.rustBackendURL
        guard !baseURL.isEmpty else {
            log("AgentPill: title gen skipped — rustBackendURL empty")
            return nil
        }
        let normalized = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let url = URL(string: normalized + "v2/chat/completions") else {
            log("AgentPill: title gen failed — bad URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        do {
            let headers = try await APIClient.shared.buildHeaders(requireAuth: true)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        } catch {
            log("AgentPill: title gen skipped — auth header unavailable (\(error.localizedDescription))")
            return nil
        }

        let prompt = """
        The user just kicked off a background agent with this request:

        "\(query)"

        Reply with a JSON object on a single line, no prose, no markdown:
        {"title":"<3-5 word imperative title in Title Case, no trailing punctuation>","ack":"<one short spoken acknowledgement, max 7 words, friendly tone, e.g. 'Got it, building Mario now.'>"}
        """

        // OpenAI-compatible body. The backend translates to Anthropic upstream.
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 120,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("AgentPill: title gen failed — no HTTP response")
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                log("AgentPill: title gen HTTP \(http.statusCode) — \(body)")
                return nil
            }
            // OpenAI shape: { choices: [{ message: { content: "..." } }] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any],
                let text = message["content"] as? String
            else {
                log("AgentPill: title gen response shape unexpected")
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payloadData = trimmed.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let ack = (payload["ack"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty, !ack.isEmpty
            else {
                log("AgentPill: title gen JSON parse failed — raw: \(String(trimmed.prefix(200)))")
                return nil
            }
            log("AgentPill: title gen ok — title=\"\(title)\" ack=\"\(ack)\"")
            return (title: String(title.prefix(40)), ack: String(ack.prefix(120)))
        } catch {
            log("AgentPill: title gen threw — \(error.localizedDescription)")
            return nil
        }
    }
}
