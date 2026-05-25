// JSON lines protocol between Swift app and Node.js agent runtime
// Extended from agent protocol with authentication message types

// === Swift → Bridge (stdin) ===

export interface QueryMessage {
  type: "query";
  id: string;
  prompt: string;
  systemPrompt: string;
  sessionKey?: string;
  cwd?: string;
  mode?: "ask" | "act";
  model?: string;
  resume?: string;
  imageBase64?: string;
}

export interface ToolResultMessage {
  type: "tool_result";
  callId: string;
  result: string;
}

export interface StopMessage {
  type: "stop";
}

export interface InterruptMessage {
  type: "interrupt";
}

export interface InvalidateSessionMessage {
  type: "invalidate_session";
  sessionKey: string;
}

/** Swift tells the bridge which auth method the user chose */
export interface AuthenticateMessage {
  type: "authenticate";
  methodId: string;
}

export interface WarmupSessionConfig {
  key: string;
  model: string;
  systemPrompt?: string;
}

/** Swift tells the bridge to pre-create an ACP session in the background */
export interface WarmupMessage {
  type: "warmup";
  cwd?: string;
  model?: string;       // backward compat
  models?: string[];    // backward compat
  sessions?: WarmupSessionConfig[];  // new: per-session config with system prompts
}

/** Swift pushes a refreshed Firebase ID token to the bridge (piMono mode) */
export interface RefreshTokenMessage {
  type: "refresh_token";
  token: string;
}

export type InboundMessage =
  | QueryMessage
  | ToolResultMessage
  | StopMessage
  | InterruptMessage
  | InvalidateSessionMessage
  | AuthenticateMessage
  | WarmupMessage
  | RefreshTokenMessage;

// === Bridge → Swift (stdout) ===

export interface InitMessage {
  type: "init";
  sessionId: string;
}

export interface TextDeltaMessage {
  type: "text_delta";
  text: string;
}

export interface ToolUseMessage {
  type: "tool_use";
  callId: string;
  name: string;
  input: Record<string, unknown>;
}

export interface ResultMessage {
  type: "result";
  text: string;
  sessionId: string;
  costUsd?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

export interface ToolActivityMessage {
  type: "tool_activity";
  name: string;
  status: "started" | "completed";
  toolUseId?: string;
  input?: Record<string, unknown>;
}

export interface ToolResultDisplayMessage {
  type: "tool_result_display";
  toolUseId: string;
  name: string;
  output: string;
}

export interface ThinkingDeltaMessage {
  type: "thinking_delta";
  text: string;
}

export interface ErrorMessage {
  type: "error";
  message: string;
}

/** Sent when ACP requires user authentication (OAuth) */
export interface AuthRequiredMessage {
  type: "auth_required";
  methods: AuthMethod[];
  authUrl?: string;
}

export interface AuthMethod {
  id: string;
  type: "agent_auth" | "env_var" | "terminal";
  displayName?: string;
  args?: string[];
  env?: Record<string, string>;
}

/** Sent after successful authentication */
export interface AuthSuccessMessage {
  type: "auth_success";
}

/**
 * Periodic liveness signal emitted while a turn is in flight. Lets the
 * Swift `StallDetector` distinguish "bridge is alive but the upstream
 * model is slow" from "bridge subprocess is dead." See
 * `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md` PR 8.
 *
 * - `turnId` matches the corresponding `QueryMessage.id`.
 * - `uptimeMs` is the time since the bridge started this turn.
 * - `upstreamLastEventMs` is the time since the most recent
 *   non-heartbeat outbound message (text_delta, tool_use, etc.). Long
 *   `upstreamLastEventMs` while heartbeats keep arriving = upstream is
 *   slow but the bridge is fine.
 *
 * Cadence: 5 s (PR 8 default; tuned in PR 9).
 *
 * Back-compat: Swift's parser drops unknown message types via a
 * `default: log + return nil` (AgentBridge.swift parseMessage), so an
 * older Swift client receiving this message just logs and continues —
 * safe to roll the bridge forward independently.
 */
export interface HeartbeatMessage {
  type: "heartbeat";
  turnId: string;
  uptimeMs: number;
  upstreamLastEventMs: number;
}

export type OutboundMessage =
  | InitMessage
  | TextDeltaMessage
  | ToolUseMessage
  | ToolActivityMessage
  | ToolResultDisplayMessage
  | ThinkingDeltaMessage
  | ResultMessage
  | ErrorMessage
  | AuthRequiredMessage
  | AuthSuccessMessage
  | HeartbeatMessage;
