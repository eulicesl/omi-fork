// PR 8: heartbeat protocol contract tests.
//
// These tests don't exercise the live bridge (no subprocess spawned —
// the existing pi-mono-adapter.test.ts already mocks that). Instead
// they verify the protocol-level contract: HeartbeatMessage shape is
// part of OutboundMessage, the type narrows correctly, and the
// fake-bridge-scenarios heartbeat-loss scenario emits the same shape
// the real bridge will.

import { describe, expect, it } from "vitest";
import type { OutboundMessage, HeartbeatMessage } from "../src/protocol.js";
import {
  allScenarios,
  heartbeatLoss,
  type HeartbeatMessage as FakeHeartbeat,
} from "./fake-bridge-scenarios.js";

describe("heartbeat protocol", () => {
  it("HeartbeatMessage is part of the OutboundMessage union", () => {
    // Compile-time contract: a value of this shape must be assignable
    // to OutboundMessage. If a future edit removes HeartbeatMessage
    // from the union, this fails at typecheck before runtime.
    const heartbeat: OutboundMessage = {
      type: "heartbeat",
      turnId: "turn-1",
      uptimeMs: 5000,
      upstreamLastEventMs: 3000,
    };
    expect(heartbeat.type).toBe("heartbeat");
  });

  it("HeartbeatMessage shape matches the fake-bridge declaration", () => {
    // PR 0b forward-declared HeartbeatMessage in the test-side file;
    // PR 8 added the real one to protocol.ts. The two declarations
    // must remain structurally identical so test fixtures stay
    // representative of production payloads.
    const fakeShape: FakeHeartbeat = {
      type: "heartbeat",
      turnId: "turn-1",
      uptimeMs: 5000,
      upstreamLastEventMs: 3000,
    };
    const protocolShape: HeartbeatMessage = fakeShape;
    expect(protocolShape).toEqual(fakeShape);
  });

  it("heartbeat_loss scenario emits real-protocol-shaped heartbeats", () => {
    const script = heartbeatLoss(3, 5_000);
    const heartbeats = script.messages.filter(
      (m): m is { delayMs: number; message: HeartbeatMessage } =>
        m.message.type === "heartbeat",
    );
    expect(heartbeats).toHaveLength(3);
    for (const tm of heartbeats) {
      expect(tm.message.turnId).toBeTruthy();
      expect(tm.message.uptimeMs).toBeGreaterThan(0);
      expect(tm.message.upstreamLastEventMs).toBeGreaterThanOrEqual(0);
    }
  });

  it("heartbeat_loss scenario does not include a terminal result", () => {
    // The whole point of the loss scenario: heartbeats stop arriving
    // and nothing follows. PR 8's Swift detector reads this as
    // .bridgeUnresponsive after the configured threshold.
    const script = heartbeatLoss();
    const hasResult = script.messages.some((m) => m.message.type === "result");
    const hasError = script.messages.some((m) => m.message.type === "error");
    expect(hasResult).toBe(false);
    expect(hasError).toBe(false);
  });

  it("no other scenario emits heartbeats by default", () => {
    // Heartbeats appear only in the dedicated heartbeat_loss scenario
    // for now. PR 8's Node bridge implementation emits them inline
    // during every turn, but the scripts in fake-bridge-scenarios.ts
    // are pre-bridge fixtures — they're message sequences a consumer
    // would observe. Adding heartbeats to other scenarios is fine
    // when needed but currently isolated to keep test intent clear.
    for (const scenario of allScenarios()) {
      if (scenario.name === "heartbeat_loss") continue;
      const beats = scenario.messages.filter((m) => m.message.type === "heartbeat");
      expect(beats, `${scenario.name} should not emit heartbeats`).toHaveLength(0);
    }
  });
});
