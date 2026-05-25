// PR 0b: smoke test for the deterministic fake bridge scenarios.
// Parallels the Swift FakeAgentBridgeTests determinism contract.

import { describe, expect, it } from "vitest";
import {
  allScenarios,
  happyPath,
  type FakeBridgeScript,
} from "./fake-bridge-scenarios.js";

describe("fake bridge scenarios", () => {
  it("inventory matches the roadmap (11 scenarios in declaration order)", () => {
    const names = allScenarios().map((s) => s.name);
    expect(names).toEqual([
      "happy_path",
      "first_token_delay",
      "mid_stream_stall",
      "never_returning_tool",
      "malformed_message",
      "bridge_crash_mid_turn",
      "heartbeat_loss",
      "auth_required",
      "interrupt_during_tool",
      "delayed_final_result",
      "empty_tool_result",
    ]);
  });

  it("every scenario starts with init and has at least one message", () => {
    for (const scenario of allScenarios()) {
      expect(scenario.messages.length).toBeGreaterThan(0);
      const first = scenario.messages[0];
      expect(first.delayMs).toBe(0);
      expect(first.message.type).toBe("init");
    }
  });

  it("delays are non-decreasing within each scenario", () => {
    for (const scenario of allScenarios()) {
      let prev = -1;
      for (const m of scenario.messages) {
        expect(m.delayMs, `${scenario.name} delays must not regress`).toBeGreaterThanOrEqual(prev);
        prev = m.delayMs;
      }
    }
  });

  it("happy_path terminates with a result", () => {
    const script = happyPath();
    const last = script.messages[script.messages.length - 1].message;
    expect(last.type).toBe("result");
  });

  // The PR 0b acceptance gate: scenarios are pure data and must
  // produce identical output across 100 consecutive invocations.
  it("every scenario is deterministic across 100 invocations", () => {
    for (let run = 0; run < 100; run++) {
      const fresh = allScenarios();
      expect(fresh, `divergence at run ${run}`).toEqual(allScenarios());
    }
  });

  it("returns fresh objects each call (no shared mutation)", () => {
    const a = happyPath();
    const b = happyPath();
    expect(a).not.toBe(b);
    expect(a.messages).not.toBe(b.messages);
    // Mutating one must not affect the other.
    (a.messages as Array<unknown>).push("sentinel" as never);
    expect(b.messages.length).toBe(a.messages.length - 1);
  });

  // Defensive: the Swift inventory test fails if you add/remove a
  // scenario without updating both sides. This is the JS-side mirror.
  it("scenario count matches Swift inventory (11 total: 1 baseline + 10 failure modes)", () => {
    expect(allScenarios().length).toBe(11);
  });
});

// Type-level assertion that FakeBridgeScript is exported correctly.
// If this fails, the export signature drifted.
const _typeCheck: FakeBridgeScript = happyPath();
void _typeCheck;
