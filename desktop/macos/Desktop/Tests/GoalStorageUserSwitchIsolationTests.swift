import XCTest

@testable import Omi_Computer

/// BUG-002 verification (audit fff46934). DRAFT — authored in a Linux container and
/// NOT compiled; verify the build on macOS before trusting a red/green result.
///
/// Designed to FAIL against the current, unfixed code — a failure IS the confirmation.
///
/// Root cause: `GoalStorage` (and 4 sibling actors) cache the resolved per-user
/// `DatabasePool` in `_dbQueue` and expose `invalidateCache()`, but `AuthService.signOut`
/// (`AuthService.swift:2090-2095`) invalidates only 6 other storages and never calls it.
/// This test reproduces the underlying stale-pool leak by switching the active user
/// WITHOUT invalidating GoalStorage's cache — exactly what sign-out fails to do.
///
/// Two possible non-green outcomes on current code:
///   (a) the cached pool stays open  -> getLocalGoals() returns user A's goal (assertion fails), or
///   (b) close() tore down that pool -> getLocalGoals() throws (test errors).
/// Either way it is not green. The test asserts the correct post-fix behavior (empty for B).
final class GoalStorageUserSwitchIsolationTests: XCTestCase {

  private var userA: String!
  private var userB: String!
  private var dirA: URL!
  private var dirB: URL!

  private func userDir(_ uid: String) -> URL {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Omi", isDirectory: true)
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(uid, isDirectory: true)
  }

  override func setUp() async throws {
    try await super.setUp()
    userA = "goal-isolation-A-\(UUID().uuidString)"
    userB = "goal-isolation-B-\(UUID().uuidString)"
    dirA = userDir(userA)
    dirB = userDir(userB)
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    await GoalStorage.shared.invalidateCache()
    RewindDatabase.currentUserId = nil
    try? FileManager.default.removeItem(at: dirA)
    try? FileManager.default.removeItem(at: dirB)
    try await super.tearDown()
  }

  /// EXPECTED TO FAIL on current code: after switching from A to B without invalidating
  /// GoalStorage's cache, B must not see A's goal.
  func testGoalStorageDoesNotServePreviousUsersGoalsAfterSwitch() async throws {
    // ---- User A: create a goal (this caches A's DatabasePool inside GoalStorage) ----
    await GoalStorage.shared.invalidateCache()
    RewindDatabase.currentUserId = userA
    try await RewindDatabase.shared.initialize()

    let now = Date()
    let goalA = GoalRecord(
      backendId: nil, backendSynced: false,
      title: "User A private goal",
      goalDescription: nil, goalType: "numeric",
      targetValue: 100, currentValue: 0, minValue: 0, maxValue: 100,
      unit: nil, isActive: true, completedAt: nil,
      deleted: false, createdAt: now, updatedAt: now)
    _ = try await GoalStorage.shared.insertLocalGoal(goalA)

    let goalsSeenByA = try await GoalStorage.shared.getLocalGoals()
    XCTAssertEqual(goalsSeenByA.count, 1, "precondition: user A sees their own goal")

    // ---- Switch to user B WITHOUT GoalStorage.invalidateCache() (models sign-out gap) ----
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = userB
    try await RewindDatabase.shared.initialize()

    let goalsSeenByB = try await GoalStorage.shared.getLocalGoals()
    XCTAssertTrue(
      goalsSeenByB.isEmpty,
      "BUG-002: after a user switch, GoalStorage must not serve the previous user's goals — its cached DatabasePool is never invalidated on sign-out, so B reads A's database")
  }
}
