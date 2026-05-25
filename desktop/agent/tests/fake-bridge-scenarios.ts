// Parallel scenario set to the Swift FakeBridgeScenario, emitting real
// OutboundMessage shapes (plus a heartbeat-ahead-of-protocol type and a
// malformed/crash sentinel) so PR 8's bridge-heartbeat tests have a
// deterministic event source.
//
// PR 0b ships these as pure data with a smoke test asserting determinism.
// No consumer wires them up yet; that lands in PR 8.

import type { OutboundMessage } from "../src/protocol.js";

/**
 * PR 8 will add this to protocol.ts and the Node bridge will emit it.
 * Defined locally for now so scenarios can carry the shape today.
 */
export interface HeartbeatMessage {
  type: "heartbeat";
  turnId: string;
  uptimeMs: number;
  upstreamLastEventMs: number;
}

/**
 * Test sentinels — not real protocol messages. The Node bridge surfaces
 * these out of band (malformed lines get logged + skipped; crashes
 * surface via process termination). The fake fires them as discrete
 * events so consumers can observe them without a real subprocess.
 */
export interface MalformedSentinel {
  type: "__malformed";
  rawLine: string;
}

export interface CrashSentinel {
  type: "__bridge_crash";
}

export type FakeOutboundMessage =
  | OutboundMessage
  | HeartbeatMessage
  | MalformedSentinel
  | CrashSentinel;

export interface TimedMessage {
  delayMs: number;
  message: FakeOutboundMessage;
}

export interface FakeBridgeScript {
  name: string;
  messages: TimedMessage[];
}

const at = (delayMs: number, message: FakeOutboundMessage): TimedMessage => ({
  delayMs,
  message,
});

// ─────────────────────────────────────────────────────────────────────
// Baseline
// ─────────────────────────────────────────────────────────────────────

export const happyPath = (): FakeBridgeScript => ({
  name: "happy_path",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(100, { type: "text_delta", text: "Hello" }),
    at(200, { type: "text_delta", text: " world" }),
    at(300, { type: "text_delta", text: "." }),
    at(400, {
      type: "result",
      text: "Hello world.",
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10,
      outputTokens: 3,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  ],
});

// ─────────────────────────────────────────────────────────────────────
// Failure scenarios (mirror FakeBridgeScenario in Swift)
// ─────────────────────────────────────────────────────────────────────

export const firstTokenDelay = (ms: number = 12_000): FakeBridgeScript => ({
  name: "first_token_delay",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(ms, { type: "text_delta", text: "Sorry for the wait." }),
    at(ms + 100, {
      type: "result",
      text: "Sorry for the wait.",
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10,
      outputTokens: 5,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  ],
});

export const midStreamStall = (
  deltasBeforeStall: number = 3,
  stallDurationMs: number = 30_000,
): FakeBridgeScript => {
  const messages: TimedMessage[] = [
    at(0, { type: "init", sessionId: "fake-session" }),
  ];
  let t = 100;
  for (let i = 0; i < deltasBeforeStall; i++) {
    messages.push(at(t, { type: "text_delta", text: `chunk${i} ` }));
    t += 100;
  }
  const resumeAt = t + stallDurationMs;
  messages.push(at(resumeAt, { type: "text_delta", text: "back." }));
  messages.push(
    at(resumeAt + 100, {
      type: "result",
      text: "stalled then back.",
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10,
      outputTokens: deltasBeforeStall + 1,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  );
  return { name: "mid_stream_stall", messages };
};

export const neverReturningTool = (
  toolName: string = "execute_sql",
  waitMs: number = 60_000,
): FakeBridgeScript => ({
  name: "never_returning_tool",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(50, { type: "text_delta", text: "Let me look that up." }),
    at(100, {
      type: "tool_use",
      callId: "call-1",
      name: toolName,
      input: { sql: "SELECT 1" },
    }),
    at(150, {
      type: "tool_activity",
      name: toolName,
      status: "started",
      toolUseId: "call-1",
      input: { sql: "SELECT 1" },
    }),
    at(150 + waitMs, {
      type: "error",
      message: "fake_scenario_never_returning_tool",
    }),
  ],
});

export const malformedMessage = (beforeMs: number = 100): FakeBridgeScript => ({
  name: "malformed_message",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(beforeMs, { type: "__malformed", rawLine: "{this is not valid json" }),
    at(beforeMs + 100, { type: "text_delta", text: "Recovered." }),
    at(beforeMs + 200, {
      type: "result",
      text: "Recovered.",
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10,
      outputTokens: 1,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  ],
});

export const bridgeCrashMidTurn = (afterMs: number = 500): FakeBridgeScript => ({
  name: "bridge_crash_mid_turn",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(100, { type: "text_delta", text: "Working on it…" }),
    at(afterMs, { type: "__bridge_crash" }),
  ],
});

export const heartbeatLoss = (
  initialHeartbeats: number = 2,
  intervalMs: number = 5_000,
): FakeBridgeScript => {
  const messages: TimedMessage[] = [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(50, { type: "text_delta", text: "Thinking…" }),
  ];
  for (let i = 1; i <= initialHeartbeats; i++) {
    messages.push(
      at(i * intervalMs, {
        type: "heartbeat",
        turnId: "fake-turn",
        uptimeMs: i * intervalMs,
        upstreamLastEventMs: 50,
      }),
    );
  }
  return { name: "heartbeat_loss", messages };
};

export const authRequired = (beforeMs: number = 100): FakeBridgeScript => ({
  name: "auth_required",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(beforeMs, {
      type: "auth_required",
      methods: [
        { id: "agent_auth", type: "agent_auth" },
        { id: "env_var", type: "env_var" },
      ],
      authUrl: "https://example.test/oauth",
    }),
  ],
});

export const interruptDuringTool = (
  toolName: string = "execute_sql",
  interruptAfterMs: number = 2_000,
): FakeBridgeScript => ({
  // The interrupt itself is delivered by the test runner; the script
  // describes only the messages the bridge would have emitted if no
  // interrupt arrived. Test runners cut the message stream at the
  // simulated interrupt timestamp.
  name: "interrupt_during_tool",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(50, {
      type: "tool_use",
      callId: "call-1",
      name: toolName,
      input: { sql: "SELECT slow()" },
    }),
    at(100, {
      type: "tool_activity",
      name: toolName,
      status: "started",
      toolUseId: "call-1",
      input: { sql: "SELECT slow()" },
    }),
    at(interruptAfterMs + 10_000, {
      type: "tool_activity",
      name: toolName,
      status: "completed",
      toolUseId: "call-1",
    }),
  ],
});

export const delayedFinalResult = (
  deltasMs: number[] = [100, 200, 300],
  resultMs: number = 8_000,
): FakeBridgeScript => {
  const messages: TimedMessage[] = [
    at(0, { type: "init", sessionId: "fake-session" }),
  ];
  deltasMs.forEach((t, i) =>
    messages.push(at(t, { type: "text_delta", text: `d${i} ` })),
  );
  messages.push(
    at(resultMs, {
      type: "result",
      text: deltasMs.map((_, i) => `d${i} `).join(""),
      sessionId: "fake-session",
      costUsd: 0.001,
      inputTokens: 10,
      outputTokens: deltasMs.length,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  );
  return { name: "delayed_final_result", messages };
};

export const emptyToolResult = (
  toolName: string = "execute_sql",
): FakeBridgeScript => ({
  name: "empty_tool_result",
  messages: [
    at(0, { type: "init", sessionId: "fake-session" }),
    at(50, {
      type: "tool_use",
      callId: "call-1",
      name: toolName,
      input: { sql: "SELECT 1 WHERE 0" },
    }),
    at(100, {
      type: "tool_activity",
      name: toolName,
      status: "started",
      toolUseId: "call-1",
    }),
    at(120, {
      type: "tool_activity",
      name: toolName,
      status: "completed",
      toolUseId: "call-1",
    }),
    at(130, {
      type: "tool_result_display",
      toolUseId: "call-1",
      name: toolName,
      output: "",
    }),
    at(200, { type: "text_delta", text: "I don't have anything on that." }),
    at(300, {
      type: "result",
      text: "I don't have anything on that.",
      sessionId: "fake-session",
      costUsd: 0.0005,
      inputTokens: 10,
      outputTokens: 8,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    }),
  ],
});

// ─────────────────────────────────────────────────────────────────────
// Inventory
// ─────────────────────────────────────────────────────────────────────

/**
 * All scenarios in declaration order. Matches Swift `FakeBridgeScenario.all()`.
 */
export const allScenarios = (): FakeBridgeScript[] => [
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
];
