# Omi macOS Runtime Verification Report

> **Template — fill on macOS.** No results are pre-filled: this report was scaffolded in a Linux container that could not run the app. Each bug block carries its audit *prediction* (from commit `fff46934`); you supply the runtime *result* + evidence. Do not mark `Confirmed` without attached runtime evidence.

## Metadata

- Repository: `eulicesl/omi-fork`
- Branch: `claude/omi-macos-audit-skjwgd`
- Commit SHA under test: `______`
- Audit report commit: `fff46934`
- macOS version: `______`
- Xcode version: `______`
- Build command: `______`
- Run method: `______`
- Verification date: `______`

## Summary

- Bugs attempted: `___ / 16`
- Bugs confirmed: `___`
- Bugs not reproducible: `___`
- Bugs inconclusive: `___`
- Bugs needing special setup: `___`
- Recommended first fix PR: `______`

## Verified Bugs

<!-- Duplicate this block per bug. Pull the "Original audit classification / prediction" from RUNBOOK.md. -->

### BUG-___: [Title]
- Original audit classification: `High-Confidence Code Inspection Bug` (Severity: `___`)
- Runtime verification result: `Confirmed | Not reproducible | Inconclusive | Needs different setup`
- Severity after verification: `___`
- Reproduction status: `deterministic | intermittent | one-off | none`
- Steps used: `______`
- Expected: `______`
- Actual: `______`
- Evidence captured: `screenshot | recording | log | TSan | crash trace | XCTest result`
- Logs/screenshots/video path: `evidence/BUG-___/`
- Notes: `______`
- Should block PR until fixed: `yes | no`
- Suggested PR grouping: `PR-_`

## Not Reproducible

<!-- Bugs run but not observed; note why (wrong build channel, missing device, guarded path, etc.). -->

## Inconclusive / Needs More Setup

<!-- e.g. BUG-005 needs a TSan build; BUG-010 needs a device; BUG-007 needs packet capture; BUG-009 needs a stable-channel title. -->

## Updated PR Plan (confirmed bugs only)

<!-- Build this from bugs that reached Confirmed (or high-confidence with evidence). Per PR: -->
### PR-_: [title]
- Bugs included: `______`
- Evidence available: `______`
- Risk level: `Low | Medium | High`
- Files likely touched: `______`
- Test plan: `______`
- Visual proof required: `yes | no`
- Suggested review order: `______`

## Final Recommendation
- Do not open fix PRs until approved.
- First 1–3 fix PRs recommended after approval: `______`
