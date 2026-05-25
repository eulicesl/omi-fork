import XCTest

@testable import Omi_Computer

final class ChatErrorStateTests: XCTestCase {

  // MARK: - Exhaustive recovery coverage

  /// Every `ChatErrorState` case must have a `primaryRecovery`. Implemented
  /// as an exhaustive switch so adding a new case here forces the
  /// implementation to provide a recovery action (compiler enforced).
  func testEveryCaseHasARecoveryAction() {
    let cases: [ChatErrorState] = [
      .authRequired,
      .timeout(toolName: nil),
      .timeout(toolName: "search"),
      .bridgeUnavailable(reason: .nodeMissing),
      .bridgeUnavailable(reason: .runtimeMissing),
      .bridgeUnavailable(reason: .crashed),
      .bridgeUnavailable(reason: .unknown),
      .interrupted,
      .noDataFound,
    ]

    for state in cases {
      // Exhaustive switch — any new case added to ChatErrorRecoveryAction
      // without being assigned here will fail to compile.
      switch state.primaryRecovery {
      case .retry, .signIn, .openSettings, .installRuntime, .dismiss, .switchMode:
        break
      }
    }

    // Spot-check the canonical mappings so a refactor that swaps recoveries
    // around fails loudly.
    XCTAssertEqual(ChatErrorState.authRequired.primaryRecovery, .signIn)
    XCTAssertEqual(ChatErrorState.timeout(toolName: nil).primaryRecovery, .retry)
    XCTAssertEqual(ChatErrorState.interrupted.primaryRecovery, .retry)
    XCTAssertEqual(ChatErrorState.noDataFound.primaryRecovery, .dismiss)
    XCTAssertEqual(
      ChatErrorState.bridgeUnavailable(reason: .nodeMissing).primaryRecovery,
      .installRuntime
    )
    XCTAssertEqual(
      ChatErrorState.bridgeUnavailable(reason: .runtimeMissing).primaryRecovery,
      .installRuntime
    )
    XCTAssertEqual(
      ChatErrorState.bridgeUnavailable(reason: .crashed).primaryRecovery,
      .retry
    )
    XCTAssertEqual(
      ChatErrorState.bridgeUnavailable(reason: .unknown).primaryRecovery,
      .retry
    )
  }

  // MARK: - BridgeError → ChatErrorState

  func testFromBridgeErrorMapsTimeoutToTimeout() {
    let mapped = ChatErrorState.from(.timeout)
    XCTAssertEqual(mapped, .timeout(toolName: nil))
  }

  func testFromBridgeErrorMapsStoppedToInterrupted() {
    let mapped = ChatErrorState.from(.stopped)
    XCTAssertEqual(mapped, .interrupted)
  }

  func testFromBridgeErrorReturnsNilForUnmappableCases() {
    // These should fall through to the existing generic errorMessage banner
    // / paywall sheets rather than the new card.
    XCTAssertNil(ChatErrorState.from(.encodingError))
    XCTAssertNil(
      ChatErrorState.from(
        .quotaExceeded(
          plan: "Free", unit: "cost_usd", used: 5.0, limit: 5.0, resetAtUnix: nil)
      )
    )
    XCTAssertNil(ChatErrorState.from(.agentError("something opaque went wrong")))
  }

  // MARK: - Bridge-unavailable reason coverage

  func testBridgeUnavailableReasonsCoverNodeMissing() {
    let mapped = ChatErrorState.from(.nodeNotFound)
    XCTAssertEqual(mapped, .bridgeUnavailable(reason: .nodeMissing))
  }

  func testBridgeUnavailableReasonsCoverRuntimeMissing() {
    let mapped = ChatErrorState.from(.bridgeScriptNotFound)
    XCTAssertEqual(mapped, .bridgeUnavailable(reason: .runtimeMissing))
  }

  func testBridgeUnavailableReasonsCoverCrashed() {
    XCTAssertEqual(
      ChatErrorState.from(.processExited),
      .bridgeUnavailable(reason: .crashed)
    )
    XCTAssertEqual(
      ChatErrorState.from(.outOfMemory),
      .bridgeUnavailable(reason: .crashed)
    )
  }

  func testBridgeUnavailableReasonsCoverUnknown() {
    let mapped = ChatErrorState.from(.notRunning)
    XCTAssertEqual(mapped, .bridgeUnavailable(reason: .unknown))
  }

  // MARK: - Auth mapping

  func testFromBridgeErrorMapsAuthMissingToAuthRequired() {
    let mapped = ChatErrorState.from(.authMissing)
    XCTAssertEqual(mapped, .authRequired)
  }
}
